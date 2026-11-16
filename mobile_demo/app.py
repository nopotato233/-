"""Run: python -m uvicorn mobile_demo.app:app --host 0.0.0.0 --port 8000."""
import ast
import io
import os
import threading
from contextlib import asynccontextmanager
from pathlib import Path

import numpy as np
import onnxruntime as ort
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageOps, UnidentifiedImageError
from dotenv import load_dotenv

from mobile_demo.guidance import DeepSeekGuide
from starlette.concurrency import run_in_threadpool

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / '.env')
MAX_BYTES = 5 * 1024 * 1024
Image.MAX_IMAGE_PIXELS = 16_000_000


def prepare(image, size):
    width, height = image.size
    scale = min(size / width, size / height)
    resized = (round(width * scale), round(height * scale))
    left, top = (size - resized[0]) // 2, (size - resized[1]) // 2
    canvas = Image.new('RGB', (size, size), (114, 114, 114))
    canvas.paste(image.resize(resized), (left, top))
    tensor = np.asarray(canvas, dtype=np.float32).transpose(2, 0, 1)[None] / 255.0
    return tensor, scale, left, top


def decode(output, scale, left, top, width, height, names, confidence=0.35):
    # Standard YOLOv8 detection export: [1, 4 + classes, anchors].
    rows = output[0].T
    scores = rows[:, 4:].max(axis=1)
    classes = rows[:, 4:].argmax(axis=1)
    mask = scores >= confidence
    rows, scores, classes = rows[mask], scores[mask], classes[mask]
    if not len(rows):
        return []
    boxes = np.column_stack((rows[:, 0] - rows[:, 2] / 2,
                             rows[:, 1] - rows[:, 3] / 2,
                             rows[:, 0] + rows[:, 2] / 2,
                             rows[:, 1] + rows[:, 3] / 2))
    boxes[:, [0, 2]] = np.clip((boxes[:, [0, 2]] - left) / scale, 0, width)
    boxes[:, [1, 3]] = np.clip((boxes[:, [1, 3]] - top) / scale, 0, height)
    order = np.argsort(scores)[::-1][:1000]
    keep = []
    while len(order) and len(keep) < 100:
        i, rest = order[0], order[1:]
        keep.append(i)
        a = np.maximum(boxes[i, :2], boxes[rest, :2])
        b = np.minimum(boxes[i, 2:], boxes[rest, 2:])
        intersection = np.maximum(b - a, 0).prod(axis=1)
        areas = np.maximum(boxes[:, 2:] - boxes[:, :2], 0).prod(axis=1)
        iou = intersection / np.maximum(areas[i] + areas[rest] - intersection, 1e-9)
        order = rest[(iou <= 0.45) | (classes[rest] != classes[i])]
    return [{'label': names.get(int(classes[i]), str(classes[i])),
             'confidence': round(float(scores[i]), 3),
             'box': boxes[i].round(1).tolist()} for i in keep]


class Detector:
    def __init__(self):
        self.session = ort.InferenceSession(
            os.environ.get('MODEL_PATH', str(ROOT / 'yolov8n.onnx')),
            providers=['CPUExecutionProvider'])
        self.input = self.session.get_inputs()[0]
        self.size = self.input.shape[2]
        metadata = self.session.get_modelmeta().custom_metadata_map
        self.names = ast.literal_eval(metadata.get('names', '{}'))
        self.lock = threading.Lock()

    def predict_image(self, image):
        tensor, scale, left, top = prepare(image, self.size)
        with self.lock:
            output = self.session.run(None, {self.input.name: tensor})[0]
        return {'width': image.width, 'height': image.height, 'backend': 'yolo',
                'detections': decode(output, scale, left, top, image.width,
                                     image.height, self.names)}


def read_image(data):
    try:
        with Image.open(io.BytesIO(data)) as source:
            return ImageOps.exif_transpose(source).convert('RGB')
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise HTTPException(400, '请上传有效且尺寸适中的图片') from exc


@asynccontextmanager
async def lifespan(app):
    app.state.backend = 'yolo'
    app.state.guide = DeepSeekGuide()
    app.state.detector = Detector()
    yield


app = FastAPI(title='探步 · 跨平台视觉助手', lifespan=lifespan)
STATIC = Path(__file__).parent / 'static'
app.mount('/static', StaticFiles(directory=STATIC), name='static')


@app.get('/')
def index():
    return FileResponse(STATIC / 'index.html', headers={'Cache-Control': 'no-cache'})


@app.get('/manifest.webmanifest')
def manifest():
    return FileResponse(STATIC / 'manifest.webmanifest', media_type='application/manifest+json')


@app.get('/service-worker.js')
def service_worker():
    return FileResponse(STATIC / 'service-worker.js', media_type='application/javascript',
                        headers={'Cache-Control': 'no-cache', 'Service-Worker-Allowed': '/'})


@app.get('/health')
def health(request: Request):
    state = request.app.state
    return {'status': 'ok', 'backend': 'yolo', 'model': 'yolov8n.onnx',
            'runtime': 'ONNX Runtime CPU', 'guidance_model': state.guide.model,
            'guidance_configured': bool(state.guide.key)}


async def predict_request(request):
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > MAX_BYTES:
            raise HTTPException(413, '图片不能超过 5 MB')
    image = await run_in_threadpool(read_image, bytes(data))
    try:
        return await run_in_threadpool(request.app.state.detector.predict_image, image)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, '视觉推理失败，请检查模型路径和运行环境') from exc


@app.post('/detect')
async def detect(request: Request):
    return await predict_request(request)


@app.post('/analyze')
async def analyze(request: Request):
    result = await predict_request(request)
    result['guidance'] = await request.app.state.guide.describe(result)
    return result
