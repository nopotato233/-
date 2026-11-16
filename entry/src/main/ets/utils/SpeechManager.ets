import { textToSpeech } from '@kit.CoreSpeechKit';

export class SpeechManager {
  private static instance: SpeechManager | null = null;
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private isInitialized: boolean = false;

  private constructor() {}

  public static getInstance(): SpeechManager {
    if (!SpeechManager.instance) {
      SpeechManager.instance = new SpeechManager();
    }
    return SpeechManager.instance;
  }

  // 初始化引擎（建议在页面加载时调用）
  public async init(): Promise<void> {
    if (this.isInitialized) return;

    let initParamsInfo: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: 0,   // 0 是聆小珊女声
      online: 1,   // 1 是离线模式
    };

    try {
      this.ttsEngine = await textToSpeech.createEngine(initParamsInfo);
      this.isInitialized = true;
      console.info('TTS 引擎初始化成功');
    } catch (err) {
      console.error('TTS 引擎初始化失败: ' + JSON.stringify(err));
    }
  }

  // 播报文本
  public async speak(text: string, speed: number = 1.0): Promise<void> {
    if (!this.ttsEngine) {
      console.error('TTS 引擎还没初始化');
      return;
    }

    const requestId = `speak_${Date.now()}`;

    let speakListener: textToSpeech.SpeakListener = {
      onStart: (rid) => console.info('TTS 开始播报: ' + rid),
      onComplete: (rid) => console.info('TTS 播报完成: ' + rid),
      onStop: (rid) => console.info('TTS 停止播报: ' + rid),
      onError: (rid, code, msg) => console.error(`TTS 出错: ${code} - ${msg}`),
      onData: () => {}
    };

    this.ttsEngine.setListener(speakListener);

    let speakParams: textToSpeech.SpeakParams = {
      requestId: requestId,
      extraParams: {
        'queueMode': 0,
        'speed': speed,      // 语速
        'volume': 1.0,
        'pitch': 1.0,
        'languageContext': 'zh-CN',
        'audioType': 'pcm',
        'playType': 1
      }
    };

    try {
      await this.ttsEngine.speak(text, speakParams);
    } catch (err) {
      console.error('TTS 播报失败: ' + JSON.stringify(err));
    }
  }

  // 停止播报
  public stop(): void {
    if (this.ttsEngine) {
      this.ttsEngine.stop();
    }
  }

  // 释放引擎（页面关闭时调用）
  public shutdown(): void {
    if (this.ttsEngine) {
      this.ttsEngine.shutdown();
      this.ttsEngine = null;
      this.isInitialized = false;
    }
  }
}