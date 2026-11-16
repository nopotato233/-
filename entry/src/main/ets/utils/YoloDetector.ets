// utils/YoloDetector.ets
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

// COCO 80类标签
const COCO_LABELS: string[] = [
  '人', '自行车', '汽车', '摩托车', '飞机', '公交车', '火车', '卡车', '船',
  '红绿灯', '消防栓', '停止标志', '停车计时器', '长椅', '鸟', '猫', '狗',
  '马', '羊', '牛', '大象', '熊', '斑马', '长颈鹿', '背包', '雨伞',
  '手提包', '领带', '行李箱', '飞盘', '滑雪板', '单板滑雪', '运动球',
  '风筝', '棒球棒', '棒球手套', '滑板', '冲浪板', '网球拍', '瓶子',
  '红酒杯', '杯子', '叉子', '刀', '勺子', '碗', '香蕉', '苹果',
  '三明治', '橙子', '西兰花', '胡萝卜', '热狗', '披萨', '甜甜圈',
  '蛋糕', '椅子', '沙发', '盆栽', '床', '餐桌', '马桶', '电视',
  '笔记本电脑', '鼠标', '遥控器', '键盘', '手机', '微波炉', '烤箱',
  '烤面包机', '水槽', '冰箱', '书', '时钟', '花瓶', '剪刀', '泰迪熊',
  '吹风机', '牙刷'
];

export interface BoundingBox {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface DetectedObject {
  label: string;
  labelId: number;
  score: number;
  box: BoundingBox;
}

export class YoloDetector {
  private model: mindSporeLite.Model | null = null;
  private context: common.UIAbilityContext;
  private readonly MODEL_NAME: string = 'yolov8n.ms';
  private readonly INPUT_SIZE: number = 640;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async loadModel(): Promise<boolean> {
    try {
      const rawFileContent: Uint8Array =
        await this.context.resourceManager.getRawFileContent(this.MODEL_NAME);
      const modelBuffer: ArrayBuffer = rawFileContent.buffer as ArrayBuffer;

      const cpuConfig: mindSporeLite.CpuDevice = {
        threadNum: 4,
        threadAffinityMode: mindSporeLite.ThreadAffinityMode.BIG_CORES_FIRST,
        precisionMode: 'enforce_fp32'
      };

      const msContext: mindSporeLite.Context = {
        target: ['cpu'],
        cpu: cpuConfig
      };

      this.model = await mindSporeLite.loadModelFromBuffer(modelBuffer, msContext);
      hilog.info(0xFF00, 'YoloDetector', '模型加载成功（CPU）');
      return true;
    } catch (error) {
      const e = error as BusinessError;
      hilog.error(0xFF00, 'YoloDetector',
        `模型加载失败: code=${e.code}, message=${e.message}`);
      return false;
    }
  }

  async detect(inputBuffer: Float32Array): Promise<DetectedObject[]> {
    if (this.model === null) {
      hilog.error(0xFF00, 'YoloDetector', '模型未加载');
      return [];
    }

    if (!inputBuffer) {
      hilog.error(0xFF00, 'YoloDetector', 'inputBuffer 为 undefined');
      return [];
    }

    try {
      const modelInputs: mindSporeLite.MSTensor[] = this.model.getInputs();

      if (!modelInputs || modelInputs.length === 0) {
        hilog.error(0xFF00, 'YoloDetector', 'getInputs 返回空');
        return [];
      }

      const inputTensor = modelInputs[0];
      if (!inputTensor) {
        hilog.error(0xFF00, 'YoloDetector', 'modelInputs[0] 为 undefined');
        return [];
      }

      inputTensor.setData(inputBuffer.buffer);

      const outputs: mindSporeLite.MSTensor[] = await this.model.predict(modelInputs);

      if (!outputs || outputs.length === 0) {
        hilog.error(0xFF00, 'YoloDetector', 'predict 输出为空');
        return [];
      }

      return this.parseOutput(outputs);
    } catch (error) {
      const e = error as BusinessError;
      hilog.error(0xFF00, 'YoloDetector',
        `推理失败: code=${e.code}, message=${e.message}`);
      return [];
    }
  }

  /**
   * YOLOv8 输出格式：[1, 84, 8400]
   * 84 = 4 坐标 + 80 类别，没有单独置信度
   * 注意：数据是转置的，按列访问
   */
  private parseOutput(outputs: mindSporeLite.MSTensor[]): DetectedObject[] {
    if (!outputs || outputs.length === 0) return [];

    const rawData = outputs[0].getData();
    if (!rawData) {
      hilog.error(0xFF00, 'YoloDetector', 'getData 返回 undefined');
      return [];
    }

    const outputData = new Float32Array(rawData);
    const results: DetectedObject[] = [];
    const numClasses = 80;
    const numBoxes = 8400;

    // 1. 遍历 8400 个框，提取分数 > 0.45 的目标
    for (let i = 0; i < numBoxes; i++) {
      let maxClassScore = 0;
      let maxClassId = -1;
      for (let c = 0; c < numClasses; c++) {
        const classScore = outputData[(4 + c) * numBoxes + i];
        if (classScore > maxClassScore) {
          maxClassScore = classScore;
          maxClassId = c;
        }
      }

      if (maxClassScore < 0.45) continue;

      const cx = outputData[0 * numBoxes + i] / this.INPUT_SIZE;
      const cy = outputData[1 * numBoxes + i] / this.INPUT_SIZE;
      const w = outputData[2 * numBoxes + i] / this.INPUT_SIZE;
      const h = outputData[3 * numBoxes + i] / this.INPUT_SIZE;

      const box: BoundingBox = {
        left: cx - w / 2,
        top: cy - h / 2,
        width: w,
        height: h
      };

      results.push({
        label: COCO_LABELS[maxClassId] || `物体${maxClassId}`,
        labelId: maxClassId,
        score: maxClassScore,
        box: box
      });
    }

    hilog.info(0xFF00, 'YoloDetector', `NMS前解析出 ${results.length} 个目标`);

    // 2. 【核心】按置信度从高到低排序（标准 YOLO 流程）
    results.sort((a, b) => b.score - a.score);

    // 3. 【核心】NMS 非极大值抑制（合并重叠框）
    const nmsResults: DetectedObject[] = [];
    for (let i = 0; i < results.length; i++) {
      let keep = true;
      for (let j = 0; j < nmsResults.length; j++) {
        // 计算两个框的 IoU（交并比）
        const boxA = results[i].box;
        const boxB = nmsResults[j].box;

        const xA = Math.max(boxA.left, boxB.left);
        const yA = Math.max(boxA.top, boxB.top);
        const xB = Math.min(boxA.left + boxA.width, boxB.left + boxB.width);
        const yB = Math.min(boxA.top + boxA.height, boxB.top + boxB.height);

        const interArea = Math.max(0, xB - xA) * Math.max(0, yB - yA);
        const iou = interArea / (boxA.width * boxA.height + boxB.width * boxB.height - interArea);

        // 如果重叠度超过 0.45，说明是同一个物体，丢弃置信度低的那个（即当前的 results[i]）
        if (iou > 0.45) {
          keep = false;
          break;
        }
      }
      if (keep) {
        nmsResults.push(results[i]);
      }
    }

    hilog.info(0xFF00, 'YoloDetector', `NMS后剩余 ${nmsResults.length} 个目标`);

    // 返回去重且按置信度排序后的结果
    return nmsResults;
  }

  release(): void {
    if (this.model !== null) {
      this.model = null;
      hilog.info(0xFF00, 'YoloDetector', '模型已释放');
    }
  }
}