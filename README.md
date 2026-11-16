# 助盲眼镜（探步 / AI_Vision_for_Blind）

软创参赛项目，面向视觉辅助场景。本说明依据 GitHub 仓库实际文件与运行结果编写，区分原有鸿蒙工程材料和新增的手机浏览器验证程序。

> 已补齐用户提供的 `AppScope/`、`entry/`、`hvigor/` 与参赛材料。原生源码已可检查，但尚未在 DevEco Studio/鸿蒙真机编译运行。新增 Web 测试程序已运行，可验证图片目标检测与浏览器摄像头采集流程；不能据此证明实际出行避障安全性。

## 当前使用什么模型？

| 项目 | 检查结果与依据 |
| --- | --- |
| 大语言模型（LLM） | 检查补齐后的 ArkTS 源码仍未发现 LLM 权重、调用代码、API 配置或提示词。当前语音内容来自规则拼接与 TTS，不是大模型生成。 |
| 图像识别模型 | **Ultralytics YOLOv8n**，任务为目标检测，不是场景对话或图像描述。ONNX 元数据标明 `trained on coco.yaml`，包含 80 个类别，如 person、bus、car。 |
| 模型文件 | 原生加载 `entry/src/main/resources/rawfile/yolov8n.ms`（12,843,304 字节，MSL2 文件头）；Web 加载 `yolov8n.onnx`（12,824,061 字节）。另有 `yolov8n.pt`（6,534,387 字节），本次未执行 PT，也未验证三种格式权重逐层一致。 |
| ONNX 接口 | 输入 `images: float32[1,3,640,640]`，输出 `output0: float32[1,84,8400]`；前 4 通道是中心坐标/宽高，后 80 通道是类别分数。 |
| 导出信息 | 模型元数据：Ultralytics `8.4.175`、opset 11、`nms: None`。因此 Web 程序执行 letterbox、归一化、逐类 NMS 和坐标还原。 |
| MindSpore Lite | `YoloDetector.ets` 读取 `yolov8n.ms`，调用 `loadModelFromBuffer` 与 `predict`；配置 CPU、4 线程、FP32。不是 NPU 推理；`inspectNNRT()` 仅枚举设备。Web 使用 ONNX Runtime CPU。 |
| 避障、陀螺仪、语音 | `Index.ets` 基于框面积、位置、面积变化和类别进行风险排序，订阅陀螺仪判断手机稳定；`SpeechManager.ets` 使用 CoreSpeechKit TTS 播报。属于规则式提醒，尚未证明可靠避障。Web 仅输出检测结果，不复用原生语音与传感器。 |

COCO 通用检测不能覆盖全部路面风险，如坑洞、台阶、玻璃和细小障碍。识别框大小不能直接当作距离。原 README 中关于应用市场上架的说法，本次未独立核验。

## 技术与结构

原始工程配置：HarmonyOS、Hvigor（TypeScript 构建脚本）、OHPM、Hypium/Hamock；`build-profile.json5` 声明目标 SDK `26.0.0`、兼容版本 `6.1.1(24)`。这些是配置声明，不代表已经成功构建。业务使用 ArkTS/ArkUI、Stage 模型、CameraKit、ImageKit、MindSporeLiteKit、SensorServiceKit 和 CoreSpeechKit。

新增验证程序：Python 3.12、FastAPI、Uvicorn、ONNX Runtime CPU、NumPy、Pillow；前端为 HTML/CSS/JavaScript，使用 `getUserMedia`、Canvas、Fetch，无前端构建步骤，无云模型 API。

```text
.
├── README.md
├── AppScope/                # 应用标识、图标、名称
├── entry/                   # 原生 ArkTS 应用模块
│   ├── src/main/ets/        # 页面、Ability、检测器、TTS、UI 组件
│   ├── src/main/module.json5 # 相机/陀螺仪权限及入口
│   ├── src/main/resources/rawfile/yolov8n.ms
│   ├── src/test/           # 模板本地测试
│   └── src/ohosTest/       # 模板设备测试
├── hvigor/hvigor-config.json5
├── docs/                    # 参赛作品 ZIP 与原生审查说明
├── build-profile.json5       # 原生工程构建配置，引用 ./entry
├── oh-package*.json5         # OHPM 依赖与锁文件
├── hvigorfile.ts             # 鸿蒙构建入口
├── code-linter.json5         # 静态检查配置
├── yolov8n.onnx              # Web 测试实际使用的权重
├── yolov8n.pt                # 原始 PyTorch 格式文件（本次未加载）
├── mobile_demo/              # 新增：手机浏览器验证入口
│   ├── app.py                # 图像解码、预处理、ONNX 推理、NMS、HTTP API
│   ├── requirements.txt
│   ├── requirements-dev.txt
│   └── static/index.html     # 后置相机、拍照上传、结果绘制、停止与错误提示
└── tests/test_mobile_demo.py # 模型接口与后处理测试
```

数据流：手机摄像头 → 浏览器缩放/JPEG → 同一网络电脑 `/detect` → 640×640 letterbox → YOLOv8n → 置信度过滤/NMS → 浏览器绘框。前端等待一次请求完成后再等 700 ms 采集下一帧，最长边限制 960 像素；不是高帧率视频推理。页面切到后台或点击停止时会释放摄像头。

## 结构是否完善？

**核心原生模块已补齐，工程仍需验证和完善。** 相机、检测、TTS、陀螺仪、界面资源、权限声明及 MindSpore 模型均有源码/文件。参赛材料已恢复：[下载作品 ZIP](./docs/探步_AI_Vision_for_Blind_参赛作品.zip)。但仓库仍缺少 `hvigorw`/`hvigorw.bat` 启动脚本；产品引用 default 签名而 `signingConfigs` 为空，需在本机 IDE 中配置签名。不要提交个人签名私钥或本地 SDK 路径。

**原生算法仍有明显待验证点。** 当前 NMS 会跨类别互相抑制；按类别名而非目标 ID 保存历史，可能把不同的人当作同一个目标；面积变化判定要求间隔小于 800 ms，而采样间隔设为 800 ms，快速接近分支可能很少触发；语速、振动、语音开关还没有接入检测播报调用。原生预处理为拉伸到 640×640、NHWC，而 Web 为 letterbox、NCHW，两条流程不能直接等同。详见 [原生工程检查与真机测试清单](./docs/NATIVE_REVIEW.md)。

**Web 演示形成了最小可运行闭环。** 有相机/图片输入、真实模型推理、错误处理、请求体大小限制、结果绘制与自动测试，但不能替代原生 `.ms` 模型真机评测。当前没有账号鉴权，仅用于可信局域网内的个人测试，不应直接映射到公网。

## 原生鸿蒙手机测试

1. 在安装匹配 HarmonyOS SDK 的 DevEco Studio 中打开仓库根目录，执行项目同步与 OHPM 依赖安装。按 `build-profile.json5` 核对 SDK，不要仅为消除错误随意降级 API。
2. 在 Project Structure / Signing Configs 中配置自己的调试签名，关联 default 产品；使用支持所需 API 的鸿蒙实体手机。具体 SDK 与机型兼容性需以 IDE 和设备结果为准。
3. 构建 entry 模块并运行，授权摄像头，在实际预览页检查相机画面；查看日志中的模型加载成功、推理输出与 TTS 初始化状态。
4. 依照 [检查清单](./docs/NATIVE_REVIEW.md) 测试拒绝授权、前后台切换、重复进入预览、多人同类目标、传感器和语音设置。Android/iPhone 不能直接运行该鸿蒙工程，可先使用下面的浏览器测试程序。

当前云环境没有 DevEco Studio、Hvigor/OHPM 或鸿蒙 SDK，尚未构建 HAP、运行 Hypium 或连接鸿蒙手机。现有 `src/test` 与 `src/ohosTest` 主要是模板字符串断言，不能证明识别/相机功能通过。

## 在电脑启动 Web 测试

需要 Python 3.12（已实测）和 Git；无需 GPU、无需加载 `.pt`、无需安装 PyTorch。首次安装依赖需联网，运行推理不调用外部模型服务。

Windows PowerShell：

```powershell
git clone https://github.com/nopotato233/-.git AI_Vision_for_Blind
cd AI_Vision_for_Blind
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r mobile_demo/requirements.txt
.\.venv\Scripts\python.exe -m uvicorn mobile_demo.app:app --host 0.0.0.0 --port 8000
```

已有克隆则在对应目录先 `git pull --ff-only`，不需要重复克隆。

macOS/Linux：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r mobile_demo/requirements.txt
.venv/bin/python -m uvicorn mobile_demo.app:app --host 0.0.0.0 --port 8000
```

电脑打开 http://localhost:8000 。`GET /health` 检查启动状态；`POST /detect` 的请求体直接为 JPEG/PNG 等图片字节，不使用 multipart。输入上限 5 MiB、图像上限 1600 万像素；默认置信度 0.35、NMS IoU 0.45。可通过 `MODEL_PATH` 指定兼容的模型，当前只支持上述 YOLOv8 原始检测输出格式。

## 手机测试步骤

### 先测试拍照/上传

1. 在你的电脑上启动上述服务，手机与电脑连接同一个 Wi-Fi。使用 `ipconfig`（Windows）查电脑局域网 IPv4，例如 `192.168.1.10`。
2. 手机打开 `http://192.168.1.10:8000`，点击“拍照或选择图片”。不同浏览器可能打开相机或相册。
3. 查看识别结果。HTTP 局域网地址通常不能启用实时相机，但可用于先验证文件上传；上传图片会经局域网传到电脑，服务不主动保存图片。

如果无法访问：检查电脑防火墙是否允许 Python/端口 8000 的专用网络入站，检查 Wi-Fi 是否开启客户端隔离。手机的 localhost 指向手机，不能用它访问电脑。当前云端工作区的 localhost 也不是你的电脑地址，需要在本地启动服务后才能按这些步骤访问。

### 实时后置摄像头：配置受信任的 HTTPS

手机浏览器的 `getUserMedia` 需要安全上下文。局域网 HTTP 与简单忽略自签名证书警告都不能保证相机可用。

推荐在测试电脑安装 [mkcert](https://github.com/FiloSottile/mkcert)，以实际局域网地址替换示例 IP：

```powershell
mkdir certs
mkcert -install
mkcert -cert-file certs/phone.pem -key-file certs/phone-key.pem localhost 127.0.0.1 192.168.1.10
.\.venv\Scripts\python.exe -m uvicorn mobile_demo.app:app --host 0.0.0.0 --port 8443 --ssl-certfile certs/phone.pem --ssl-keyfile certs/phone-key.pem
```

使用 `mkcert -CAROOT` 找到 `rootCA.pem`，将**根证书**安装到测试手机并设置信任。iOS 通常需要安装描述文件后在“证书信任设置”开启完全信任；Android 在证书设置中安装 CA 证书，具体行为依系统和浏览器而异。证书文件扩展名可能需要改为 `.crt` 才能被手机识别。**不要复制或上传 `rootCA-key.pem` 和服务器私钥**；`certs/` 已加入忽略列表。

然后允许专用网络端口 8443，手机访问 `https://192.168.1.10:8443`，确认无证书警告，点击“开启后置摄像头”，允许权限。默认请求后置摄像头，最终由浏览器与硬件决定。IP 改变时要重新签发证书。也可使用已受手机信任的 HTTPS 反向代理，但应控制访问范围。

暂未在实体 Android/iPhone/鸿蒙手机上测试，也未验证该证书流程在你的设备上是否已配置成功。原生 HarmonyOS 相机测试需在本地 DevEco Studio 和鸿蒙真机上另行执行。

## 本次运行验证

Web 首次验证日期：2026-11-17（北京时间）；基于原仓库提交 `22916ec` 加新增 Web 程序，在 Linux、Python 3.12.14、CPU 下运行。后续从用户上传的四个 ZIP 补齐原生工程，源码与归档文件保持原样；新增说明单独记录检查发现。

- ONNX checker 检查通过；ONNX Runtime 成功加载模型，接口形状和 COCO 类别来自模型本身元数据。
- 5 项自动测试通过：letterbox/坐标还原、逐类 NMS、真实模型空白图推理与页面/健康接口、无效图片、超限请求。
- 使用 [Ultralytics 公共 bus.jpg](https://ultralytics.com/images/bus.jpg) 实际调用接口，检测到 1 辆公交车和 4 个人；公交车置信度约 0.836。3 次 HTTP 请求约 137–207 ms（含本机客户端开销），不能作为手机帧率或准确率评估。
- Chromium 浏览器以 390×844 视口验证上传、检测列表、模拟摄像头采集、停止释放与页面宽度；无页面脚本错误。模拟摄像头不代表实体手机相机已验证。
- 补齐后已静态检查原生入口、权限、模型资源与源码调用链；MSL2 文件头存在。原生 App 未运行：当前环境未配置 DevEco Studio/匹配鸿蒙 SDK，签名与设备仍需本地配置；不能将 ONNX 测试通过当作 `.ms` 推理已通过。

复现自动测试：

```powershell
.\.venv\Scripts\python.exe -m pip install -r mobile_demo/requirements-dev.txt
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

ONNX 检查器是额外开发工具（`pip install onnx`），运行 Web 不依赖它。公共图片不包含在仓库中。模型 SHA-256：

```text
yolov8n.onnx  1ee646186bdf1e4d25f52dc663587f05135c96762f3ccf7bdd8a1331e34c9e11
yolov8n.pt    31e20dde3def09e2cf938c7be6fe23d9150bbbe503982af13345706515f2ef95
```

模型元数据标示 Ultralytics AGPL-3.0 许可；使用和分发模型时需核对上游许可。原生工程、数据来源、准确率、实际出行安全性与应用市场状态不因本次演示而得到验证。
