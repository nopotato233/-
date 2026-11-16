"""Repeatable browser checks; no paid API calls or physical device claims."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import httpx
from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
SPEECH_STUB = """
window.__spoken = [];
Object.defineProperty(window, 'speechSynthesis', {configurable: true, value: {
  cancel() {}, getVoices() { return []; },
  speak(item) { window.__spoken.push({text: item.text, rate: item.rate, lang: item.lang}); }
}});
window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
"""


def run():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    url = f'http://127.0.0.1:{port}'
    env = dict(os.environ, DEEPSEEK_API_KEY='')
    with tempfile.TemporaryDirectory() as temp:
        image_path = Path(temp) / 'white.jpg'
        Image.new('RGB', (640, 480), 'white').save(image_path)
        with (Path(temp) / 'server.log').open('w') as log:
            process = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'mobile_demo.app:app',
                                        '--host', '127.0.0.1', '--port', str(port)],
                                       cwd=ROOT, env=env, stdout=log, stderr=log)
            try:
                for _ in range(80):
                    if process.poll() is not None:
                        raise RuntimeError((Path(temp) / 'server.log').read_text())
                    try:
                        if httpx.get(url + '/health', timeout=1).status_code == 200:
                            break
                    except httpx.HTTPError:
                        time.sleep(.2)
                else:
                    raise RuntimeError('Test server did not become ready')
                with sync_playwright() as p:
                    launch = {'headless': True, 'args': ['--use-fake-device-for-media-stream',
                                                       '--use-fake-ui-for-media-stream']}
                    if os.environ.get('BROWSER_EXECUTABLE'):
                        launch['executable_path'] = os.environ['BROWSER_EXECUTABLE']
                    browser = None
                    try:
                        for name, options in [
                            ('Android-sized Chromium', dict(p.devices['Pixel 7'])),
                            ('Windows-sized Chromium', {'viewport': {'width': 1366, 'height': 900}})
                        ]:
                            options.pop('default_browser_type', None)
                            context = p.chromium.launch_persistent_context(
                                str(Path(temp) / name.replace(' ', '_')), **launch,
                                **options, permissions=['camera'])
                            browser = context
                            context.add_init_script(SPEECH_STUB)
                            context.route('**/analyze', lambda route: route.fulfill(
                                json={'guidance': {'status': 'ok', 'model': 'deepseek-flash',
                                                   'text': '这是一条用于验证播报的场景说明。'}}))
                            page = context.new_page()
                            errors = []
                            page.on('pageerror', lambda error: errors.append(str(error)))
                            page.goto(url)
                            page.wait_for_function('navigator.serviceWorker.controller !== null')
                            session = context.new_cdp_session(page)
                            manifest = session.send('Page.getAppManifest')
                            assert not manifest['errors'], manifest
                            assert json.loads(manifest['data'])['display'] == 'standalone'
                            install_errors = session.send('Page.getInstallabilityErrors')['installabilityErrors']
                            assert not install_errors, install_errors
                            assert page.locator('#guide').is_disabled()
                            page.locator('#start').click()
                            page.wait_for_function("document.querySelector('#status').textContent.includes('0 个物体')")
                            assert page.locator('#camera option').count() >= 2
                            # A USB camera disconnect must stop capture instead of repeating a stale frame.
                            page.evaluate("document.querySelector('video').srcObject.getVideoTracks()[0].dispatchEvent(new Event('ended'))")
                            assert page.locator('#status').inner_text().startswith('摄像头已断开')
                            assert page.evaluate("document.querySelector('video').srcObject === null")
                            page.locator('#camera').select_option(index=1)
                            page.locator('#start').click()
                            page.wait_for_function("document.querySelector('#stop').disabled === false")
                            page.locator('#stop').click()
                            page.locator('#file').set_input_files(str(image_path))
                            page.wait_for_function("document.querySelector('#guide').disabled === false")
                            page.locator('#auto-speak').check()
                            page.locator('#speech-rate').select_option('1.2')
                            page.locator('#guide').click()
                            page.wait_for_function("document.querySelector('#guidance').textContent.startsWith('DeepSeek 场景说明')")
                            page.wait_for_function('window.__spoken.length === 1')
                            assert page.evaluate('window.__spoken[0].rate') == 1.2
                            page.locator('#speak').click()
                            assert page.evaluate('window.__spoken.length') == 2
                            # Exercise the custom install control without pretending to install into an OS.
                            page.evaluate("""() => {
                              const event = new Event('beforeinstallprompt', {cancelable: true});
                              window.__installPrompts = 0;
                              event.prompt = async () => { window.__installPrompts++; };
                              event.userChoice = Promise.resolve({outcome: 'accepted'});
                              window.dispatchEvent(event);
                            }""")
                            page.locator('#install').click()
                            assert page.evaluate('window.__installPrompts') == 1
                            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
                            cache_urls = page.evaluate("""async () => {
                              const keys = await caches.keys(), urls = [];
                              for (const key of keys) {
                                for (const request of await (await caches.open(key)).keys()) urls.push(new URL(request.url).pathname);
                              }
                              return urls;
                            }""")
                            assert '/' in cache_urls
                            assert all(path not in cache_urls for path in ['/health', '/detect', '/analyze'])
                            context.set_offline(True)
                            page.reload(wait_until='domcontentloaded')
                            page.wait_for_function("document.querySelector('#connection').textContent.includes('未连接')")
                            assert page.get_by_role('heading', name='跨平台视觉助手').is_visible()
                            assert page.locator('#guide').is_disabled()
                            assert page.evaluate("fetch('/health').then(() => false).catch(() => true)")
                            context.set_offline(False)
                            page.locator('#reconnect').click()
                            page.wait_for_function("document.querySelector('#connection').textContent.includes('已连接')")
                            assert not errors, errors
                            print(f'PASS {name}: manifest/installability, camera selection/disconnect, upload, AI UI, TTS contract, install control, offline shell and API cache exclusion')
                            context.close()
                    finally:
                        if browser is not None:
                            browser.close()
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    run()
