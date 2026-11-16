# Android / Windows 跨平台客户端

当前采用 **PWA + 共用 Python 推理服务**，保留原生鸿蒙模块。PWA 可由浏览器安装成独立应用窗口，前端不用鸿蒙 SDK。此版本不提供 APK、MSIX 或 EXE 安装包，也不把鸿蒙 ArkTS 自动转换为 Android/Windows 原生代码。

## 平台与能力

| 入口 | 相机/图片 | 语音 | 推理位置 | 安装方式 |
| --- | --- | --- | --- | --- |
| Android Chrome PWA | 手机后置优先、相机选择、拍照/图片上传 | 浏览器 SpeechSynthesis，依赖系统语音资源 | 运行 Python 服务的电脑 | 访问受信任 HTTPS 后，从安装按钮或浏览器菜单安装 |
| Windows Edge/Chrome PWA | 内置/USB 摄像头选择、图片上传 | 浏览器 SpeechSynthesis，依赖系统语音资源 | 本机 Windows Python 或同网络服务 | localhost 或受信任 HTTPS，使用浏览器安装 |
| HarmonyOS 原生 entry | CameraKit，相机权限和 ImageKit | CoreSpeechKit | 本机 MindSpore Lite，或可选远程 AI 模式 | DevEco Studio 构建和签名，仍待真机验证 |

PWA 选择 YOLOv8n ONNX Runtime CPU 服务，DeepSeek V4.1 Flash 只接收检测摘要。SAM 3 暂不接入。浏览器不加载 PT/MS 权重，也不持有 DeepSeek 密钥。Android PWA 当前不是手机端离线推理方案；Windows 本机 YOLO 可在依赖安装后不联网运行，但 DeepSeek 仍需互联网。

```text
Android Chrome PWA ─┐
Windows PWA ────────┼─ 同源 HTTP(S) /detect、/analyze → Python YOLO → DeepSeek 场景说明
鸿蒙远程 AI 模式 ──┘
鸿蒙原生离线模式 ──── MindSpore Lite yolov8n.ms
```

## Windows 本机启动

安装 Python 3.12 和较新的 Microsoft Edge/Chrome。在仓库根目录打开 PowerShell：

```powershell
.\scripts\start-windows.ps1
```

脚本在项目目录建立 `.venv`、安装运行依赖、启动 localhost:8000 服务，服务就绪后尝试打开浏览器；保持终端运行，Ctrl+C 停止服务。不修改系统执行策略。若本机策略不允许执行脚本，使用根 README 中的手动 venv/pip/uvicorn 命令即可。

需要 AI 场景说明时，将 `.env.example` 复制为 `.env`，填写自己的密钥并重启服务。不要提交 `.env`。不配置密钥仍能使用 YOLO，生成说明时会明确提示不可用。

```powershell
Copy-Item .env.example .env
notepad .env
```

访问 `http://localhost:8000`，在 Edge/Chrome 地址栏或菜单中选择安装。浏览器没有显示页面安装按钮时也可以检查浏览器菜单；企业策略、无痕模式和浏览器版本可能限制安装。安装入口不可用时仍可在普通标签页使用。

Windows 上首次使用摄像头时，允许网站权限，并检查“设置 → 隐私和安全性 → 相机”中的访问权限。若设备被会议软件占用，关闭占用后重试。下拉菜单支持切换内置/USB 摄像头；断开当前设备会停止采集。

PWA 图标不会自动启动 Python 服务。关闭服务后再次打开应用，只能看到缓存界面和连接提示；先运行启动脚本再点“检查连接”。卸载可通过浏览器应用管理或系统应用列表完成。

## Android 连接 Windows 服务

1. 手机与 Windows 电脑处于同一可信局域网，查出电脑的局域网 IP。
2. 配置包含该 IP/域名且被手机信任的 HTTPS 证书；可按根 README 中的 mkcert 测试步骤操作。不关闭证书验证，不依赖“忽略警告”开启相机。
3. 在 Windows 启动 HTTPS 服务，明确监听局域网地址：

```powershell
.\scripts\start-windows.ps1 -ListenAddress 0.0.0.0 -Port 8443 -CertFile certs/phone.pem -KeyFile certs/phone-key.pem -NoBrowser
```

4. 在专用网络防火墙中允许选定端口，手机 Chrome 打开 `https://电脑局域网IP:8443`。确认无证书错误，允许摄像头权限，使用“开启摄像头”或“拍照上传”。
5. 通过页面“安装应用”按钮（浏览器提供时）或 Chrome 菜单安装到主屏幕。安装后首次启动同样需要相机权限。

手机的 localhost 是手机自己，不能用来访问 Windows 电脑。局域网 HTTP 通常只能先测试文件上传，不能满足实时相机及 PWA 安装的安全上下文要求。浏览器不支持 PWA 安装时仍可使用 HTTPS 标签页。

## 通用交互

- 选择摄像头、开启、停止；切换设备时停止旧相机。切后台或网络离线时释放相机并取消未完成请求。
- 分开提供“选择图片”和“拍照上传”，兼容电脑文件选择与手机拍照入口。
- 点击“生成场景说明”暂停采集，说明带采集时间，只对应静止画面。不会自动按视频帧调用付费 API。
- “朗读说明”或勾选自动播报，支持慢/标准/快；“停止朗读”立即取消。具体中文声音由浏览器/系统决定，有的语音资源可能需要网络。不支持语音 API 的浏览器显示文字提示。
- 重新开启相机或换图片会清除旧 AI 说明，避免将旧文本当作新画面的结论。

## 离线与更新

Service Worker 只缓存根页面、CSS、JS、manifest 和图标。**不缓存 /health、图片上传、检测框结果或 DeepSeek 响应**。首次在线访问且缓存成功后，离线可以打开界面；无法连接推理服务时检测不可用，不能把“离线打开”理解成“Android 离线识别”。Windows 的 localhost 服务在外网断开但本机仍运行时仍可执行 YOLO。

新版本在线访问会更新界面缓存。Service Worker 有新版本时通常在旧窗口关闭后激活；发布壳资源结构变化时需更新缓存版本。不要在缓存中加入密钥、用户画面或 API 响应。

当前服务无账号鉴权，含可用 DeepSeek 密钥时仅供可信局域网使用，不直接暴露公网。所有说明都用于技术测试，不应作为实际出行指令。

## 验证情况与复现

本次在 Linux 上运行，13 项 Python 自动测试通过，包含真实 ONNX 推理、PWA 资源、scope、图标尺寸及私密文件不被静态目录暴露。

浏览器测试使用 Chromium 的 Android 尺寸/移动输入模拟和 Windows 桌面尺寸，验证：manifest、安装条件、模拟相机选择/断开、图片上传、AI 说明 UI、语音 API 调用、安装按钮、离线重开及 API 不缓存。AI 返回和语音引擎使用模拟，不产生收费 API 请求，也不代表真实扬声器播报成功。

```powershell
.\.venv\Scripts\python.exe -m pip install -r tests/requirements-browser.txt
.\.venv\Scripts\python.exe -m playwright install chromium
.\.venv\Scripts\python.exe tests/browser_smoke.py
```

Linux 使用 `.venv/bin/python`；已有 Chromium 可用 `BROWSER_EXECUTABLE` 指定路径。新增 GitHub Actions：Ubuntu/Windows Python 测试、Windows 启动脚本语法检查、Ubuntu Chromium 流程检查；以实际工作流结果为准，不能将“已配置 CI”视为“全部平台已通过”。

仍待实体设备验收：

- [ ] Android Chrome 的实际 PWA 安装、后置相机、多摄像头切换、后台释放与中文语音。
- [ ] Windows 10/11 Edge/Chrome 的实际安装、PowerShell 启动、内置/USB 摄像头与中文语音。
- [ ] 手机连接 Windows 的证书、局域网、防火墙、延迟与网络断开恢复。
- [ ] 鸿蒙原生模块的编译、签名与真机测试。
