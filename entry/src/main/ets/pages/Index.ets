import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { requestCameraPermission } from '../entryability/PermissionHelper';
import { SpeechManager } from '../utils/SpeechManager';
import { YoloDetector, DetectedObject } from '../utils/YoloDetector';
import { deviceInfo } from '@kit.BasicServicesKit';
import { BreathingCircle } from '../ui/components/BreathingCircle';
import { sensor } from '@kit.SensorServiceKit';
import { AppColors, PAGE_GRADIENT } from '../ui/AppTheme';

@Entry
@Component
struct Index {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack()
  @State private promptOpacity: number = 0
  @State private promptOffset: number = 20
  @State private speechSpeed: string = '标准'
  @State private vibrationEnabled: boolean = true
  @State private voiceHintEnabled: boolean = true

  private xComponentController: XComponentController = new XComponentController();
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private captureSession: camera.Session | null = null;
  private previewSurfaceId: string = '';
  private imageReceiver: image.ImageReceiver | null = null;
  private receiverSurfaceId: string = '';
  private lastDetectTime: number = 0;
  private detectInterval: number = 800;
  private isDetecting: boolean = false;
  private yoloDetector: YoloDetector | null = null;
  private sensorCallback: ((data: sensor.GyroscopeResponse) => void) | null = null;
  @State isPreviewing: boolean = false;

  private isPhoneStable: boolean = true;
  private lastObjectState: Map<string, Map<string, number>> = new Map();
  private lastSpokenText: string = '';
  private lastSpeakTime: number = 0;

  onObjectDetected(objects: DetectedObject[]): void {
    if (objects.length === 0) return;

    // 1. 过滤掉常见误识别物品，以及太小的噪点
    const ignoreLabels = ['冰箱', '电视', '微波炉', '烤箱', '床', '马桶', '水槽'];
    objects = objects.filter(obj => {
      const isIgnored = ignoreLabels.includes(obj.label);
      const isTooSmall = (obj.box.width * obj.box.height) < 0.03;

      // 【防反光】过滤掉长宽比极其奇怪的框（比如细长的反光）
      const aspectRatio = obj.box.width / obj.box.height;
      const isWeirdShape = aspectRatio > 3 || aspectRatio < 0.33;

      return !isIgnored && !isTooSmall && !isWeirdShape;
    });

    if (objects.length === 0) return;

    const now = Date.now();

    let highestThreatObj: DetectedObject | null = null;
    let highestThreatScore = -1;
    let finalSpeech = '';
    let isDanger = false;

    for (let i = 0; i < objects.length; i++) {
      const obj = objects[i];
      const currentArea = obj.box.width * obj.box.height;
      const centerX = obj.box.left + obj.box.width / 2;

      let positionStr = '正前方';
      if (centerX < 0.33) positionStr = '左前方';
      else if (centerX > 0.67) positionStr = '右前方';

      // 置信度是基础分（0~100分），面积只作为微调（最多加 20 分）
      let threatScore = obj.score * 100 + currentArea * 20;
      let objIsDanger = false;
      let statusStr = '';

      const distanceStr = currentArea > 0.15 ? '' : '远处';

      const lastState = this.lastObjectState.get(obj.label);
      if (lastState && this.isPhoneStable) {
        const timeDiff = now - (lastState.get('time') || 0);
        if (timeDiff > 0 && timeDiff < 800) {
          const lastArea = lastState.get('area') || 0.01;
          const areaGrowthRate = (currentArea - lastArea) / lastArea;

          if (areaGrowthRate > 0.4) {
            threatScore += 200;
            objIsDanger = true;
            statusStr = '有快速冲过来的';
          } else if (areaGrowthRate > 0.1) {
            threatScore += 50;
            statusStr = '有正在靠近的';
          }
        }
      }

      const isVehicle = ['汽车', '自行车', '摩托车', '公交车', '卡车'].includes(obj.label);
      if (obj.label === '人' || isVehicle) {
        threatScore += 30;
      }

      const stateMap = new Map<string, number>();
      stateMap.set('area', currentArea);
      stateMap.set('time', now);
      this.lastObjectState.set(obj.label, stateMap);

      if (threatScore > highestThreatScore) {
        highestThreatScore = threatScore;
        highestThreatObj = obj;

        let dodgeDir = '停步';
        if (centerX < 0.33) dodgeDir = '向右躲';
        else if (centerX > 0.67) dodgeDir = '向左躲';

        if (objIsDanger) {
          finalSpeech = `警告！${positionStr}，${dodgeDir}！${statusStr}${obj.label}`;
          isDanger = true;
        } else if (statusStr) {
          finalSpeech = `${distanceStr}${positionStr}${statusStr}${obj.label}`;
        } else {
          finalSpeech = `${distanceStr}${positionStr}有${obj.label}`;
        }
      }
    }

    if (highestThreatObj) {
      // 1.5 秒内同样的东西不重复报
      if (finalSpeech === this.lastSpokenText && (now - this.lastSpeakTime < 1500)) {
        return;
      }

      console.info(`[TTS播报] ${finalSpeech} (危险状态: ${isDanger})`);

      // 【核心优化：只在必要时打断】
      const isCompletelyNew = !finalSpeech.includes(this.lastSpokenText) && !this.lastSpokenText.includes(finalSpeech);

      if (isDanger || isCompletelyNew) {
        SpeechManager.getInstance().stop();
        setTimeout(() => {
          SpeechManager.getInstance().speak(finalSpeech);
        }, 50);
      } else {
        SpeechManager.getInstance().speak(finalSpeech);
      }

      this.lastSpokenText = finalSpeech;
      this.lastSpeakTime = now;
    }
  }  // ← 这个是闭合 onObjectDetected 方法的！

  aboutToAppear(): void {
    SpeechManager.getInstance().init();
    this.startWelcomeAnimation();
    this.inspectNNRT();
    this.initGyroscope();

    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;

    this.yoloDetector = new YoloDetector(context);
    this.yoloDetector.loadModel().then((success: boolean) => {
      if (success) {
        console.info('YOLO 模型加载成功');
      } else {
        console.error('YOLO 模型加载失败');
      }
    });

    requestCameraPermission(context).then((granted) => {
      if (!granted) {
        console.error('权限未授予');
      }
    });
  }

  private startWelcomeAnimation(): void {
    this.promptOpacity = 0
    this.promptOffset = 20
    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 1000,
        curve: Curve.EaseOut
      }, () => {
        this.promptOpacity = 1
        this.promptOffset = 0
      })
    }, 700)
  }

  private initGyroscope(): void {
    try {
      this.sensorCallback = (data: sensor.GyroscopeResponse) => {
        const angularVelocity = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z);

        // 【照妖镜】：只要摇手机，控制台就会疯狂刷这行
        console.info(`[陀螺仪] 当前角速度: ${angularVelocity.toFixed(2)}, 手机平稳: ${this.isPhoneStable}`);

        if (angularVelocity > 0.8) {
          this.isPhoneStable = false;
        } else {
          this.isPhoneStable = true;
        }
      };
      sensor.on(sensor.SensorId.GYROSCOPE, this.sensorCallback, { interval: 100000000 });
      console.info('陀螺仪传感器已启动');
    } catch (error) {
      console.error('陀螺仪启动失败: ' + JSON.stringify(error));
    }
  }

  private inspectNNRT(): void {
    try {
      const devices = mindSporeLite.getAllNNRTDeviceDescriptions();
      console.info(`[NNRT] device count = ${devices.length}`);
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[NNRT] enumeration failed: code=${err.code}, message=${err.message}`);
    }
  }

  aboutToDisappear(): void {
    SpeechManager.getInstance().shutdown();
    this.releaseCamera();
    if (this.yoloDetector) {
      this.yoloDetector.release();
      this.yoloDetector = null;
    }
    if (this.sensorCallback) {
      sensor.off(sensor.SensorId.GYROSCOPE, this.sensorCallback);
    }
  }

  async initCamera(): Promise<void> {
    if (!this.previewSurfaceId) {
      console.error('SurfaceId 未就绪');
      return;
    }

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.cameraManager = camera.getCameraManager(context);

      const cameras = this.cameraManager.getSupportedCameras();
      const backCamera = cameras.find(
        cam => cam.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK
      ) || cameras[0];

      if (!backCamera) {
        console.error('未找到可用相机');
        return;
      }

      this.cameraInput = this.cameraManager.createCameraInput(backCamera);
      await this.cameraInput.open();

      const outputCapability = this.cameraManager.getSupportedOutputCapability(
        backCamera, camera.SceneMode.NORMAL_PHOTO
      );

      let previewProfile = outputCapability.previewProfiles[0];
      for (let i = 1; i < outputCapability.previewProfiles.length; i++) {
        const p = outputCapability.previewProfiles[i];
        if (p.size.width * p.size.height > previewProfile.size.width * previewProfile.size.height) {
          previewProfile = p;
        }
      }
      console.info(`选中的预览尺寸: ${previewProfile.size.width}x${previewProfile.size.height}`);

      this.previewOutput = this.cameraManager.createPreviewOutput(
        previewProfile, this.previewSurfaceId
      );

      const receiverSize: image.Size = {
        width: previewProfile.size.width,
        height: previewProfile.size.height
      };

      this.imageReceiver = image.createImageReceiver(
        receiverSize, image.ImageFormat.JPEG, 8
      );
      this.receiverSurfaceId = await this.imageReceiver.getReceivingSurfaceId();

      this.imageReceiver.on('imageArrival', () => {
        this.imageReceiver?.readNextImage((err: BusinessError, nextImage: image.Image) => {
          if (err || !nextImage) {
            console.error(`读取图像失败: ${err?.code}`);
            return;
          }

          const now = Date.now();
          if (now - this.lastDetectTime < this.detectInterval) {
            nextImage.release();
            return;
          }
          if (this.isDetecting) {
            nextImage.release();
            return;
          }
          this.lastDetectTime = now;
          this.isDetecting = true;

          this.detectObject(nextImage).finally(() => {
            this.isDetecting = false;
            nextImage.release();
          });
        });
      });

      const receiverOutput = this.cameraManager.createPreviewOutput(
        previewProfile, this.receiverSurfaceId
      );

      this.captureSession = this.cameraManager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.Session;
      this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);
      this.captureSession.addOutput(receiverOutput);
      await this.captureSession.commitConfig();
      await this.captureSession.start();

      this.isPreviewing = true;
      console.info('相机会话启动成功');
    } catch (err) {
      const e = err as BusinessError;
      console.error(`相机初始化失败: code=${e.code}, message=${e.message}`);
    }
  }

  async releaseCamera(): Promise<void> {
    try {
      if (this.imageReceiver) {
        this.imageReceiver.off('imageArrival');
        await this.imageReceiver.release();
        this.imageReceiver = null;
      }
      if (this.captureSession) {
        await this.captureSession.stop();
        await this.captureSession.release();
        this.captureSession = null;
      }
      if (this.previewOutput) {
        await this.previewOutput.release();
        this.previewOutput = null;
      }
      if (this.cameraInput) {
        await this.cameraInput.close();
        this.cameraInput = null;
      }
      this.isPreviewing = false;
      console.info('相机已释放');
    } catch (err) {
      const e = err as BusinessError;
      console.error(`释放失败: ${e.code} ${e.message}`);
    }
  }

  async detectObject(img: image.Image): Promise<void> {
    if (this.yoloDetector === null) {
      console.error('YOLO 检测器未初始化');
      return;
    }

    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;

    try {
      const component = await img.getComponent(image.ComponentType.JPEG);
      if (!component || !component.byteBuffer) {
        console.error('获取图像数据失败');
        return;
      }

      const realWidth = img.size.width;
      const realHeight = img.size.height;

      const sourceOptions: image.SourceOptions = {
        sourcePixelFormat: image.PixelMapFormat.NV21,
        sourceSize: {
          width: realWidth,
          height: realHeight
        },
        sourceDensity: 120
      };

      imageSource = image.createImageSource(component.byteBuffer, sourceOptions);
      if (!imageSource) {
        console.error('创建 ImageSource 失败');
        return;
      }

      pixelMap = await imageSource.createPixelMap();

      const inputData: Float32Array = await this.preprocessImage(pixelMap);
      if (!inputData || inputData.length === 0) {
        console.error('preprocessImage 返回空数据');
        return;
      }

      const objects: DetectedObject[] = await this.yoloDetector.detect(inputData);

      if (objects.length > 0) {
        console.info(`YOLO 识别到 ${objects.length} 个目标`);
        this.onObjectDetected(objects);
      } else {
        console.info('YOLO 未识别到目标');
      }
    } catch (err) {
      const e = err as BusinessError;
      console.error(`识别失败: code=${e.code}, message=${e.message}`);
    } finally {
      if (pixelMap) {
        pixelMap.release();
      }
      if (imageSource) {
        imageSource.release();
      }
    }
  }

  private async preprocessImage(pixelMap: image.PixelMap): Promise<Float32Array> {
    const INPUT_SIZE = 640;
    const defaultResult = new Float32Array(1 * 3 * INPUT_SIZE * INPUT_SIZE);

    try {
      const info = pixelMap.getImageInfoSync();
      if (!info || !info.size) {
        console.error('getImageInfoSync 返回空');
        return defaultResult;
      }

      const scaleX = INPUT_SIZE / info.size.width;
      const scaleY = INPUT_SIZE / info.size.height;
      await pixelMap.scale(scaleX, scaleY);

      const buffer = new ArrayBuffer(INPUT_SIZE * INPUT_SIZE * 4);
      await pixelMap.readPixelsToBuffer(buffer);
      const rgba = new Uint8Array(buffer);

      // NHWC 布局
      const float32 = new Float32Array(1 * INPUT_SIZE * INPUT_SIZE * 3);
      for (let i = 0; i < INPUT_SIZE * INPUT_SIZE; i++) {
        float32[i * 3] = rgba[i * 4] / 255.0;
        float32[i * 3 + 1] = rgba[i * 4 + 1] / 255.0;
        float32[i * 3 + 2] = rgba[i * 4 + 2] / 255.0;
      }
      return float32;
    } catch (err) {
      const e = err as BusinessError;
      console.error(`预处理失败: code=${e.code}, message=${e.message}`);
      return defaultResult;
    }
  }

  private enterRecognition(): void {
    this.pageStack.pushPath({ name: 'CameraPage' })
  }
  private openHelp(): void {
    this.pageStack.pushPath({ name: 'Help' })
  }
  private openVoiceSettings(): void {
    this.pageStack.pushPath({ name: 'VoiceSettings' })
  }
  private backToSettings(): void {
    this.pageStack.pop()
  }

  @Builder
  buildCameraPage() {
    NavDestination() {
      Stack() {
        XComponent({
          id: 'camera_preview',
          type: XComponentType.SURFACE,
          controller: this.xComponentController
        })
          .width('100%')
          .height('100%')
          .renderFit(RenderFit.RESIZE_COVER)
          .onLoad(() => {
            this.previewSurfaceId = this.xComponentController.getXComponentSurfaceId();
            this.initCamera();
          })

        Column() {
          Row() {
            Circle()
              .width(10)
              .height(10)
              .backgroundColor(AppColors.sageLight)
            Text('正在识别中')
              .fontSize(15)
              .fontColor(AppColors.white)
              .margin({ left: 8 })
          }
          .backgroundColor(AppColors.overlay)
          .padding({ left: 16, right: 18, top: 9, bottom: 9 })
          .borderRadius(20)
          .margin({ top: 54 })

          Blank()

          Column() {
            Button('退出识别')
              .width('100%')
              .height(72)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.white)
              .backgroundColor(AppColors.overlayDeep)
              .borderRadius(36)
              .border({ width: 1, color: 'rgba(255, 255, 255, 0.22)' })
              .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.28)', offsetX: 0, offsetY: 8 })
              .onClick(() => {
                this.pageStack.replacePath({ name: 'Settings' });
              })
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 72, bottom: 34 })
          .linearGradient({
            angle: 180,
            colors: [
              ['rgba(48, 54, 58, 0)', 0.0],
              ['rgba(48, 54, 58, 0.55)', 1.0]
            ]
          })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
  }

  build() {
    Navigation(this.pageStack) {
      this.buildWelcomePage()
    }
    .navDestination(this.PageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
  }

  @Builder
  PageMap(name: string) {
    if (name === 'CameraPage') {
      this.buildCameraPage()
    } else if (name === 'Settings') {
      this.buildSettingsPage()
    } else if (name === 'Help') {
      this.buildHelpPage()
    } else if (name === 'VoiceSettings') {
      this.buildVoiceSettingsPage()
    }
  }

  @Builder
  buildWelcomePage() {
    NavDestination() {
      Stack() {
        Circle()
          .width(280)
          .height(280)
          .backgroundColor(AppColors.sage)
          .opacity(0.07)
          .position({ x: '-25%', y: '-8%' })
        Circle()
          .width(220)
          .height(220)
          .backgroundColor(AppColors.sageDeep)
          .opacity(0.06)
          .position({ x: '72%', y: '76%' })

        Column() {
          Column() {
            Text('探步')
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.ink)
              .letterSpacing(4)
            Text('智能视觉辅助')
              .fontSize(16)
              .fontColor(AppColors.stone)
              .letterSpacing(6)
              .margin({ top: 10 })
          }
          .margin({ top: 52 })

          Blank()

          BreathingCircle()

          Blank()

          Column() {
            Text('轻触屏幕任意位置')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.ink)
            Text('开始识别')
              .fontSize(28)
              .fontColor(AppColors.sage)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 10 })
          }
          .opacity(this.promptOpacity)
          .translate({ y: this.promptOffset })

          Row() {
            Circle()
              .width(8)
              .height(8)
              .backgroundColor(AppColors.sage)
            Text('环境感知 · 语音辅助')
              .fontSize(14)
              .fontColor(AppColors.stone)
              .margin({ left: 8 })
          }
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor('rgba(246, 247, 244, 0.65)')
          .borderRadius(22)
          .opacity(this.promptOpacity)
          .margin({ top: 30, bottom: 44 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 28, right: 28 })
        .onClick(() => {
          this.pageStack.pushPath({ name: 'CameraPage' })
        })
        .accessibilityText('轻触屏幕任意位置，开始识别')
      }
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 160, colors: PAGE_GRADIENT })
    }
    .hideTitleBar(true)
  }

  @Builder
  buildSettingsPage() {
    NavDestination() {
      Scroll() {
        Column() {
          Row() {
            Column() {
              Text('探步')
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.ink)
                .letterSpacing(2)
              Text('设置与帮助')
                .fontSize(16)
                .fontColor(AppColors.stone)
                .margin({ top: 6 })
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Stack() {
              Circle()
                .width(52)
                .height(52)
                .backgroundColor(AppColors.sage)
              Text('探')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.white)
            }
            .shadow({ radius: 14, color: 'rgba(99, 145, 138, 0.35)', offsetX: 0, offsetY: 6 })
          }
          .width('100%')
          .margin({ top: 44 })

          Column() {
            Row() {
              Text('开始使用')
                .fontSize(13)
                .fontColor(AppColors.stone)
                .letterSpacing(3)
              Blank()
            }
            .width('100%')

            Button('开始识别')
              .width('100%')
              .height(76)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.white)
              .backgroundColor(AppColors.sage)
              .borderRadius(22)
              .shadow(AppColors.shadowButton)
              .margin({ top: 16 })
              .onClick(() => { this.enterRecognition() })
              .accessibilityText('开始识别')
          }
          .width('100%')
          .padding(22)
          .backgroundColor(AppColors.card)
          .borderRadius(24)
          .shadow(AppColors.shadowCard)
          .margin({ top: 32 })

          this.buildEntryCard('说', '使用说明', '了解如何开始识别、退出识别以及使用语音辅助', () => { this.openHelp() })

          this.buildEntryCard('语', '语音设置', `当前语速：${this.speechSpeed}`, () => { this.openVoiceSettings() })

          Column() {
            Row() {
              Text('无障碍设计')
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.ink)
              Blank()
              Text('已启用')
                .fontSize(13)
                .fontColor(AppColors.sageDeep)
                .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                .backgroundColor('rgba(99, 145, 138, 0.14)')
                .borderRadius(12)
            }
            .width('100%')

            Text('大触控区域 · 语音反馈 · 振动提示')
              .fontSize(15)
              .fontColor(AppColors.stone)
              .margin({ top: 10 })

            Divider()
              .strokeWidth(0.5)
              .color(AppColors.line)
              .margin({ top: 16, bottom: 14 })

            Row() {
              Text(this.vibrationEnabled ? '振动提示：开启' : '振动提示：关闭')
                .fontSize(15)
                .fontColor(AppColors.sageDeep)
              Blank()
              Text('点击设置')
                .fontSize(14)
                .fontColor(AppColors.mist)
            }
            .width('100%')
            .onClick(() => { this.openVoiceSettings() })
          }
          .width('100%')
          .padding(22)
          .backgroundColor(AppColors.sageSoft)
          .borderRadius(24)
          .margin({ top: 18 })

          Column() {
            Text('探步')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.sage)
              .letterSpacing(2)
            Text('看见环境，听见世界')
              .fontSize(14)
              .fontColor(AppColors.mist)
              .margin({ top: 6 })
          }
          .margin({ top: 36, bottom: 40 })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
      }
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 160, colors: PAGE_GRADIENT })
    }
    .hideTitleBar(true)
  }

  @Builder
  buildEntryCard(mark: string, title: string, subtitle: string, onTap: () => void) {
    Row() {
      Stack() {
        Circle()
          .width(48)
          .height(48)
          .backgroundColor(AppColors.sageSoft)
        Text(mark)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.sageDeep)
      }

      Column() {
        Text(title)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.ink)
        Text(subtitle)
          .fontSize(14)
          .fontColor(AppColors.stone)
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })

      Text('›')
        .fontSize(28)
        .fontColor(AppColors.mist)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(AppColors.card)
    .borderRadius(24)
    .shadow(AppColors.shadowCard)
    .margin({ top: 18 })
    .onClick(onTap)
  }

  @Builder
  buildHelpPage() {
    NavDestination() {
      Scroll() {
        Column() {
          Row() {
            Stack() {
              Circle()
                .width(44)
                .height(44)
                .backgroundColor(AppColors.card)
              Text('‹')
                .fontSize(26)
                .fontColor(AppColors.ink)
                .margin({ bottom: 4 })
            }
            .shadow(AppColors.shadowCard)
            .onClick(() => { this.backToSettings() })

            Text('使用说明')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.ink)
              .margin({ left: 14 })
            Blank()
          }
          .width('100%')
          .margin({ top: 40 })

          Text('简单三步开始使用')
            .fontSize(16)
            .fontColor(AppColors.stone)
            .width('100%')
            .margin({ top: 12, bottom: 24 })

          this.buildHelpCard('01', '打开应用', '启动探步后，应用会进入待机模式。')
          this.buildHelpCard('02', '轻触任意位置', '屏幕任意位置都可以触碰，不需要寻找按钮。')
          this.buildHelpCard('03', '听取语音提示', '应用会识别环境并通过语音告诉你周围的目标。')

          Column() {
            Row() {
              Stack() {
                Circle()
                  .width(48)
                  .height(48)
                  .backgroundColor(AppColors.sageSoft)
                Text('退')
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.sageDeep)
              }
              Column() {
                Text('退出识别')
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.ink)
                Text('在识别页面点击“退出识别”，返回设置与帮助页面。')
                  .fontSize(15)
                  .fontColor(AppColors.stone)
                  .margin({ top: 7 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 16 })
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .backgroundColor(AppColors.card)
          .borderRadius(24)
          .shadow(AppColors.shadowCard)
          .margin({ top: 4, bottom: 40 })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
      }
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 160, colors: PAGE_GRADIENT })
    }
    .hideTitleBar(true)
  }

  @Builder
  buildHelpCard(number: string, title: string, description: string) {
    Row() {
      Stack() {
        if (deviceInfo.apiAvailable('26.0.0')) {
          Circle().width(52).height(52).fill(AppColors.sageSoft)
        } else {
          Circle().width(52).height(52).backgroundColor(AppColors.sageSoft)
        }
        Text(number)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.sageDeep)
      }
      .width(56)
      .height(56)

      Column() {
        Text(title)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.ink)
        Text(description)
          .fontSize(15)
          .fontColor(AppColors.stone)
          .margin({ top: 7 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 16 })
      .layoutWeight(1)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(AppColors.card)
    .borderRadius(24)
    .shadow(AppColors.shadowCard)
    .margin({ bottom: 14 })
  }

  @Builder
  buildVoiceSettingsPage() {
    NavDestination() {
      Column() {
        Row() {
          Stack() {
            Circle()
              .width(44)
              .height(44)
              .backgroundColor(AppColors.card)
            Text('‹')
              .fontSize(26)
              .fontColor(AppColors.ink)
              .margin({ bottom: 4 })
          }
          .shadow(AppColors.shadowCard)
          .onClick(() => { this.backToSettings() })

          Text('语音设置')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.ink)
            .margin({ left: 14 })
          Blank()
        }
        .width('100%')
        .margin({ top: 40 })

        Column() {
          Row() {
            Text('播报速度')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.ink)
            Blank()
            Text(`当前：${this.speechSpeed}`)
              .fontSize(14)
              .fontColor(AppColors.sageDeep)
          }
          .width('100%')

          Row() {
            this.buildSpeedButton('慢')
            this.buildSpeedButton('标准')
            this.buildSpeedButton('快')
          }
          .width('100%')
          .padding(4)
          .backgroundColor(AppColors.sageSoft)
          .borderRadius(20)
          .margin({ top: 18 })
        }
        .width('100%')
        .padding(22)
        .backgroundColor(AppColors.card)
        .borderRadius(24)
        .shadow(AppColors.shadowCard)
        .margin({ top: 30 })

        Column() {
          Row() {
            Column() {
              Text('振动提示')
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.ink)
              Text(this.vibrationEnabled ? '进入和退出识别时提供振动反馈' : '振动反馈已关闭')
                .fontSize(14)
                .fontColor(AppColors.stone)
                .margin({ top: 7 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.vibrationEnabled })
              .selectedColor(AppColors.sage)
              .switchPointColor(AppColors.white)
              .onChange((isOn: boolean) => { this.vibrationEnabled = isOn })
          }
          .width('100%')

          Divider()
            .strokeWidth(0.5)
            .color(AppColors.line)
            .margin({ top: 18, bottom: 18 })

          Row() {
            Column() {
              Text('语音提示')
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.ink)
              Text(this.voiceHintEnabled ? '进入和退出识别时播放语音提示' : '语音提示已关闭')
                .fontSize(14)
                .fontColor(AppColors.stone)
                .margin({ top: 7 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.voiceHintEnabled })
              .selectedColor(AppColors.sage)
              .switchPointColor(AppColors.white)
              .onChange((isOn: boolean) => { this.voiceHintEnabled = isOn })
          }
          .width('100%')
        }
        .width('100%')
        .padding(22)
        .backgroundColor(AppColors.card)
        .borderRadius(24)
        .shadow(AppColors.shadowCard)
        .margin({ top: 18 })

        Blank()

        Text('这些设置将在后续 TTS 集成后生效')
          .fontSize(14)
          .fontColor(AppColors.mist)
          .margin({ bottom: 30 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })
      .linearGradient({ angle: 160, colors: PAGE_GRADIENT })
    }
    .hideTitleBar(true)
  }

  @Builder
  buildSpeedButton(speed: string) {
    Button(speed)
      .layoutWeight(1)
      .height(52)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.speechSpeed === speed ? AppColors.white : AppColors.sageDeep)
      .backgroundColor(this.speechSpeed === speed ? AppColors.sage : Color.Transparent)
      .borderRadius(16)
      .shadow(this.speechSpeed === speed
        ? { radius: 10, color: 'rgba(99, 145, 138, 0.35)', offsetX: 0, offsetY: 4 }
        : { radius: 0, color: Color.Transparent })
      .onClick(() => { this.speechSpeed = speed })
  }
}