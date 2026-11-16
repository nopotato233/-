import io
import os
from unittest.mock import patch
import unittest

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image

from mobile_demo.app import app, decode, prepare


class DecodeTests(unittest.TestCase):
    def test_letterbox_and_restore(self):
        tensor, scale, left, top = prepare(Image.new('RGB', (1280, 720)), 640)
        self.assertEqual(tensor.shape, (1, 3, 640, 640))
        self.assertEqual((scale, left, top), (0.5, 0, 140))
        output = np.array([[[320], [320], [320], [180], [.9], [.1]]])
        result = decode(output, scale, left, top, 1280, 720, {0: 'person'})
        self.assertEqual(result[0]['box'], [320, 180, 960, 540])

    def test_nms_preserves_different_classes(self):
        output = np.array([[[100, 100, 100], [100, 100, 100], [60, 60, 60],
                            [60, 60, 60], [.9, .8, .1], [.1, .1, .85]]])
        result = decode(output, 1, 0, 0, 640, 640, {0: 'person', 1: 'bicycle'})
        self.assertEqual([item['label'] for item in result], ['person', 'bicycle'])


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client_context = TestClient(app)
        with patch.dict(os.environ, {'DEEPSEEK_API_KEY': ''}):
            cls.client = cls.client_context.__enter__()

    @classmethod
    def tearDownClass(cls):
        cls.client_context.__exit__(None, None, None)

    def test_real_model(self):
        buf = io.BytesIO()
        Image.new('RGB', (640, 480), 'white').save(buf, format='JPEG')
        response = self.client.post('/detect', content=buf.getvalue())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['width'], 640)
        self.assertEqual(response.json()['detections'], [])
        self.assertEqual(self.client.get('/health').status_code, 200)
        self.assertEqual(self.client.get('/').status_code, 200)

    def test_analyze_without_key(self):
        buf = io.BytesIO()
        Image.new('RGB', (32, 32), 'white').save(buf, format='JPEG')
        response = self.client.post('/analyze', content=buf.getvalue())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['guidance']['status'], 'unavailable')
        self.assertIn('detections', response.json())

    def test_pwa_assets_and_scope(self):
        response = self.client.get('/manifest.webmanifest')
        self.assertEqual(response.status_code, 200)
        self.assertIn('application/manifest+json', response.headers['content-type'])
        manifest = response.json()
        self.assertEqual(manifest['display'], 'standalone')
        self.assertEqual(manifest['scope'], '/')
        for icon in manifest['icons']:
            with Image.open(io.BytesIO(self.client.get(icon['src']).content)) as image:
                self.assertEqual(f'{image.width}x{image.height}', icon['sizes'])
        worker = self.client.get('/service-worker.js')
        self.assertEqual(worker.headers['service-worker-allowed'], '/')
        self.assertIn('no-cache', worker.headers['cache-control'])
        for path in ['/static/app.css', '/static/app.js']:
            self.assertEqual(self.client.get(path).status_code, 200)

    def test_static_mount_does_not_expose_credentials(self):
        self.assertEqual(self.client.get('/.env').status_code, 404)
        self.assertEqual(self.client.get('/static/.env').status_code, 404)

    def test_bad_image(self):
        self.assertEqual(self.client.post('/detect', content=b'invalid').status_code, 400)

    def test_large_request(self):
        self.assertEqual(self.client.post('/detect', content=b'x' * (5 * 1024 * 1024 + 1)).status_code, 413)


if __name__ == '__main__':
    unittest.main()
