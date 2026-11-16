import json
import os
import unittest
from unittest.mock import patch

import httpx

from mobile_demo.guidance import DeepSeekGuide


class GuidanceTests(unittest.IsolatedAsyncioTestCase):
    result = {'width': 640, 'height': 480, 'detections': [
        {'label': 'bus', 'confidence': .9, 'box': [1, 2, 30, 40],
         'mask': 'private-mask', 'image': 'private-image'}]}

    async def call_with_transport(self, handler):
        original = httpx.AsyncClient
        with patch.dict(os.environ, {'DEEPSEEK_API_KEY': 'test-only-key',
                                     'DEEPSEEK_MODEL': 'deepseek-flash'}):
            guide = DeepSeekGuide()
        def client(**kwargs):
            return original(transport=httpx.MockTransport(handler), **kwargs)
        with patch('mobile_demo.guidance.httpx.AsyncClient', side_effect=client):
            return await guide.describe(self.result)

    async def test_sends_summary_and_uses_model(self):
        def handler(request):
            body = json.loads(request.content)
            self.assertEqual(str(request.url), 'https://api.deepseek.com/chat/completions')
            self.assertEqual(body['model'], 'deepseek-flash')
            self.assertNotIn('private-image', request.content.decode())
            self.assertNotIn('private-mask', request.content.decode())
            self.assertEqual(len(body['messages']), 2)
            return httpx.Response(200, json={'model': 'deepseek-flash', 'choices': [
                {'message': {'content': '画面中有一辆公交车。'}}]})
        result = await self.call_with_transport(handler)
        self.assertEqual(result['status'], 'ok')
        self.assertIn('公交车', result['text'])

    async def test_provider_error_does_not_leak_body(self):
        result = await self.call_with_transport(lambda request: httpx.Response(
            401, json={'error': 'private-provider-detail'}))
        self.assertEqual(result['status'], 'unavailable')
        self.assertNotIn('private-provider-detail', json.dumps(result))

    async def test_timeout_keeps_detection_flow_available(self):
        def handler(request):
            raise httpx.ReadTimeout('test-only-key', request=request)
        result = await self.call_with_transport(handler)
        self.assertEqual(result['status'], 'unavailable')
        self.assertNotIn('test-only-key', json.dumps(result))

    async def test_empty_reply_is_explicitly_unavailable(self):
        result = await self.call_with_transport(lambda request: httpx.Response(200,
            json={'choices': [{'message': {'content': ''}}]}))
        self.assertEqual(result['status'], 'unavailable')

    async def test_missing_key_never_calls_provider(self):
        with patch.dict(os.environ, {'DEEPSEEK_API_KEY': ''}):
            guide = DeepSeekGuide()
        with patch('mobile_demo.guidance.httpx.AsyncClient') as client:
            result = await guide.describe(self.result)
            client.assert_not_called()
        self.assertEqual(result['status'], 'unavailable')
