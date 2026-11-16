'use strict';
const $ = id => document.getElementById(id);
const video = $('video'), view = $('view'), ctx = view.getContext('2d');
const pending = new Set();
let stream = null, running = false, timer = null, epoch = 0, snapshot = null;
let guidanceText = '', installPrompt = null;
const speechSupported = 'speechSynthesis' in window && 'SpeechSynthesisUtterance' in window;

function silence() { if (speechSupported) window.speechSynthesis.cancel(); }
function stopCapture() {
  running = false; epoch++; clearTimeout(timer);
  for (const request of pending) request.abort();
  pending.clear();
  stream?.getTracks().forEach(track => track.stop());
  stream = null; video.srcObject = null;
  $('start').disabled = false; $('stop').disabled = true;
  $('guide').disabled = !snapshot;
  silence();
}
function resetGuidance() {
  guidanceText = ''; $('speak').disabled = true;
  $('guidance').textContent = '尚未生成 AI 场景说明。';
}
async function requestImage(path, blob) {
  const controller = new AbortController(); pending.add(controller);
  const timeout = setTimeout(() => controller.abort(), 30000);
  try {
    const response = await fetch(path, {method: 'POST', headers: {'Content-Type': 'image/jpeg'}, body: blob, signal: controller.signal});
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(typeof data.detail === 'string' ? data.detail : `服务请求失败 (${response.status})`);
    }
    return await response.json();
  } catch (error) {
    if (error.name === 'AbortError') throw new Error('请求已停止或超时，请检查连接后重试。');
    if (error instanceof TypeError) throw new Error('无法连接识别服务。离线仅能打开界面，不能进行检测。');
    throw error;
  } finally { clearTimeout(timeout); pending.delete(controller); }
}
async function detect(source, token) {
  const canvas = document.createElement('canvas');
  const w = source.videoWidth || source.naturalWidth, h = source.videoHeight || source.naturalHeight;
  if (!w || !h) throw new Error('未取得有效画面，请重新开启相机。');
  const ratio = Math.min(1, 960 / Math.max(w, h));
  canvas.width = Math.max(1, Math.round(w * ratio)); canvas.height = Math.max(1, Math.round(h * ratio));
  canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', .8));
  if (token !== epoch) return;
  if (!blob) throw new Error('图像编码失败，请更换图片。');
  const start = performance.now(), data = await requestImage('/detect', blob);
  if (token !== epoch) return;
  snapshot = {blob, capturedAt: new Date()}; $('guide').disabled = false;
  resetGuidance(); $('empty').hidden = true;
  view.width = canvas.width; view.height = canvas.height; ctx.drawImage(canvas, 0, 0);
  ctx.lineWidth = 3; ctx.strokeStyle = '#83edcc'; ctx.font = '16px system-ui';
  $('results').replaceChildren();
  for (const item of data.detections) {
    const [x, y, x2, y2] = item.box; ctx.strokeRect(x, y, x2 - x, y2 - y);
    ctx.fillStyle = '#83edcc'; ctx.fillText(`${item.label} ${Math.round(item.confidence * 100)}%`, Math.max(0, x), Math.max(18, y - 5));
    const li = document.createElement('li'); li.textContent = `${item.label} · ${Math.round(item.confidence * 100)}%`; $('results').append(li);
  }
  $('status').textContent = `检测到 ${data.detections.length} 个物体 · ${Math.round(performance.now() - start)} ms`;
  $('connection').textContent = '识别服务已连接 · YOLOv8n';
}
async function loop(token) {
  if (!running || token !== epoch) return;
  try { await detect(video, token); }
  catch (error) { if (token === epoch) { stopCapture(); $('status').textContent = error.message; } }
  if (running && token === epoch) timer = setTimeout(() => loop(token), 700);
}
async function refreshCameras() {
  if (!navigator.mediaDevices?.enumerateDevices) return;
  const previous = $('camera').value;
  try {
    const cameras = (await navigator.mediaDevices.enumerateDevices()).filter(device => device.kind === 'videoinput');
    $('camera').replaceChildren(new Option('自动选择（手机优先后置）', ''));
    cameras.forEach((camera, i) => $('camera').add(new Option(camera.label || `摄像头 ${i + 1}`, camera.deviceId)));
    if (cameras.some(camera => camera.deviceId === previous)) $('camera').value = previous;
  } catch { $('status').textContent = '无法列出相机，可尝试自动选择或图片上传。'; }
}
async function startCapture() {
  stopCapture(); snapshot = null; resetGuidance(); $('guide').disabled = true;
  const token = epoch; $('start').disabled = true;
  let next = null;
  try {
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) throw new Error('相机需要受信任的 HTTPS 或电脑 localhost。也可先使用图片上传。');
    const deviceId = $('camera').value;
    next = await navigator.mediaDevices.getUserMedia({video: { ...(deviceId ? {deviceId: {exact: deviceId}} : {facingMode: {ideal: 'environment'}}), width: {ideal: 1280}}, audio: false});
    if (token !== epoch) { next.getTracks().forEach(track => track.stop()); return; }
    next.getVideoTracks().forEach(track => track.addEventListener('ended', () => {
      if (token === epoch) { stopCapture(); $('status').textContent = '摄像头已断开，请重新选择设备。'; }
    }));
    stream = next; video.srcObject = stream; await video.play();
    if (token !== epoch) { next.getTracks().forEach(track => track.stop()); return; }
    running = true; $('stop').disabled = false;
    await refreshCameras();
    if (running && token === epoch) loop(token);
  } catch (error) {
    next?.getTracks().forEach(track => track.stop());
    if (token === epoch) {
      stopCapture();
      const messages = {NotAllowedError: '未获得相机权限，请检查浏览器和系统的隐私设置。', NotFoundError: '未找到摄像头，请连接设备或选择图片。', NotReadableError: '摄像头被占用或无法读取，请关闭其他使用相机的应用。', OverconstrainedError: '所选摄像头已不可用，请选择其他设备。'};
      $('status').textContent = messages[error.name] || error.message;
    }
  }
}
async function upload(input) {
  stopCapture(); snapshot = null; resetGuidance(); $('guide').disabled = true;
  const file = input.files[0]; if (!file) return;
  const token = epoch, url = URL.createObjectURL(file);
  try {
    const image = new Image(); image.src = url; await image.decode();
    if (token !== epoch) return;
    $('status').textContent = '正在识别图片…'; await detect(image, token);
  } catch (error) { if (token === epoch) $('status').textContent = error.message; }
  finally { URL.revokeObjectURL(url); input.value = ''; }
}
function speak() {
  if (!speechSupported || !guidanceText) return;
  silence();
  const utterance = new SpeechSynthesisUtterance(guidanceText); utterance.lang = 'zh-CN';
  utterance.rate = Number($('speech-rate').value);
  const voice = window.speechSynthesis.getVoices().find(item => item.lang.startsWith('zh'));
  if (voice) utterance.voice = voice;
  utterance.onerror = () => { $('speech-status').textContent = '播报未完成，请检查系统语音组件，或再次点击朗读。'; };
  window.speechSynthesis.speak(utterance);
}
async function generateGuidance() {
  if (!snapshot) return;
  stopCapture(); const token = epoch, frame = snapshot;
  resetGuidance(); $('guide').disabled = true;
  $('status').textContent = '采集已暂停，正在分析当前静止画面。';
  $('guidance').textContent = '正在生成场景说明…';
  try {
    const data = await requestImage('/analyze', frame.blob);
    if (token !== epoch) return;
    const ok = data.guidance.status === 'ok';
    $('guidance').textContent = `${ok ? 'DeepSeek 场景说明' : 'AI 说明不可用'}：${data.guidance.text}（${frame.capturedAt.toLocaleTimeString()} 的静止画面，非实时导航）`;
    if (ok) { guidanceText = data.guidance.text; $('speak').disabled = !speechSupported; if ($('auto-speak').checked) speak(); }
  } catch (error) { if (token === epoch) $('guidance').textContent = error.message; }
  finally { if (token === epoch) $('guide').disabled = !snapshot; }
}
async function checkHealth() {
  try {
    const response = await fetch('/health', {cache: 'no-store', signal: AbortSignal.timeout(5000)});
    if (!response.ok) throw new Error('Unavailable');
    const data = await response.json();
    $('connection').textContent = `识别服务已连接 · ${data.model} · AI ${data.guidance_configured ? '已配置' : '未配置密钥'}`;
  } catch { $('connection').textContent = '未连接识别服务 · 离线只能打开界面'; }
}
$('start').onclick = startCapture;
$('stop').onclick = () => { stopCapture(); $('status').textContent = '摄像头已停止'; };
$('camera').onchange = () => { if (running) startCapture(); };
$('file').onchange = event => upload(event.target);
$('photo').onchange = event => upload(event.target);
$('guide').onclick = generateGuidance;
$('speak').onclick = speak; $('silence').onclick = silence;
$('auto-speak').onchange = () => { if (!$('auto-speak').checked) silence(); };
$('reconnect').onclick = checkHealth;
if (!speechSupported) { $('auto-speak').disabled = true; $('silence').disabled = true; $('speech-status').textContent = '当前浏览器不支持语音播报，可直接阅读说明。'; }
window.addEventListener('beforeinstallprompt', event => { event.preventDefault(); installPrompt = event; $('install').hidden = false; });
$('install').onclick = async () => {
  if (!installPrompt) return;
  const prompt = installPrompt; installPrompt = null; $('install').hidden = true;
  try { await prompt.prompt(); await prompt.userChoice; } catch { $('install-hint').textContent = '请从浏览器菜单安装应用。'; }
};
window.addEventListener('appinstalled', () => { $('install').hidden = true; $('install-hint').textContent = '应用已安装，可从桌面或开始菜单打开。'; });
if (window.matchMedia('(display-mode: standalone)').matches) $('install-hint').textContent = '正在应用窗口中运行。';
document.addEventListener('visibilitychange', () => { if (document.hidden) { stopCapture(); $('status').textContent = '页面已隐藏，采集与播报已停止。'; } });
window.addEventListener('pagehide', stopCapture);
window.addEventListener('offline', () => { stopCapture(); $('connection').textContent = '网络离线 · 检测与 AI 说明不可用'; });
window.addEventListener('online', checkHealth);
navigator.mediaDevices?.addEventListener('devicechange', refreshCameras);
if ('serviceWorker' in navigator && window.isSecureContext) navigator.serviceWorker.register('/service-worker.js').catch(() => { $('install-hint').textContent = '应用缓存暂不可用；请保持识别服务在线，并检查浏览器设置。'; });
checkHealth(); refreshCameras();
