import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';

export interface SceneGuidance {
  status: string;
  model: string;
  text: string;
}

export interface SceneAnalysis {
  guidance: SceneGuidance;
}

// API keys remain on the Python server. The phone sends a JPEG to /analyze.
export class RemoteVisionClient {
  static async analyze(pixelMap: image.PixelMap, baseUrl: string): Promise<SceneAnalysis> {
    const endpoint = baseUrl.trim().replace(/\/$/, '');
    if (!endpoint.startsWith('https://')) {
      throw new Error('请在设置中配置受信任的 HTTPS AI 服务地址');
    }
    const info = pixelMap.getImageInfoSync();
    const scale = Math.min(1, 960 / Math.max(info.size.width, info.size.height));
    if (scale < 1) await pixelMap.scale(scale, scale);
    const packer = image.createImagePacker();
    const request = http.createHttp();
    try {
      const jpeg = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 75 });
      const response = await request.request(`${endpoint}/analyze`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'image/jpeg' },
        extraData: jpeg,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 30000
      });
      if (response.responseCode !== 200) {
        throw new Error(`AI 服务请求失败 (${response.responseCode})`);
      }
      const result = JSON.parse(response.result as string) as SceneAnalysis;
      if (!result.guidance || typeof result.guidance.text !== 'string') {
        throw new Error('AI 服务未返回有效说明');
      }
      return result;
    } finally {
      request.destroy();
      await packer.release();
    }
  }
}
