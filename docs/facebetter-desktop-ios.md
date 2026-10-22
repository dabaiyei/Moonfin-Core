# Windows / iOS 视频美颜

## 在应用内配置授权（推荐）

进入 **设置 → 播放 → 视频美颜 → 美颜授权**，填写 License Token，或同时填写
App ID / App Key。页面显示当前平台和应用标识，用于在 Facebetter 控制台绑定授权。
Token / App Key 默认遮罩，数据存入当前设备的安全存储，不写入普通偏好、账号同步、
日志或 Git。Android 手机和 Android TV 各自保存授权。
保存后立即应用，已存在的美颜引擎会在帧处理线程重建；清除授权后保持原画。
若系统安全存储无法写入，页面显示失败，不会报告保存成功。

下文的构建时授权文件是可选预置方式。普通用户通过设置配置即可，无需重新打包。
本机保存的授权优先于预置值，清除操作也会覆盖预置授权。


沿用 Android 的六项本地参数：磨皮、美白、红润、锐化、瘦脸、大眼。
入口位于设置 → 播放 → 视频美颜，以及播放器的美颜按钮。默认关闭，参数范围 0–100。
Facebetter 为需授权的二进制 SDK；示例仓库和 Moonfin 的开源许可证不授予 SDK 使用权。

## Windows x64

使用 Facebetter C++ SDK **2.1.1**。本地 `packages/media_kit_video` 保留原来固定版本
`50013aee7429633ae2df656982167ca6d21237ce` 的代码和 MIT 许可证。

美颜在 mpv 的真实帧渲染回调中执行：硬件路径从 ANGLE 的输出帧缓冲读取 RGBA，
在 SDK 独立上下文中处理后写回该帧缓冲，再由 Flutter 显示纹理。读回与写回分别处理
行方向，并恢复 EGL、GL 状态。软件回退路径直接处理 mpv 软件渲染输出。
预览播放器不选为美颜目标。原来的硬件解码及高分辨率纹理路径仍可用。
CPU/GPU 数据往返有性能成本，帧率需要目标设备实测。

开启美颜且已配置授权时，SDR 播放使用应用内纹理，HDR 使用原来的原生窗口。
关闭美颜时重新按原来的渲染设置选择输出。缺少 SDK 或授权时使用原来的渲染选择。
限 SDR、最长边 1920 / 最短边 1080；超过 30fps 时限 1280×720，最高 60fps。
HDR、Dolby Vision、BT.2020、超限分辨率和帧率不应用美颜。软件渲染回退本身保留
上游的最高 1080p 限制。

1. 从 [官方 2.1.1 发布页](https://github.com/pixpark/facebetter-sdk/releases/tag/v2.1.1)
   下载 `facebetter-sdk-2.1.1-windows-x64.zip`。
2. 解压到 `windows/facebetter-sdk/`，目录下应有 `include/facebetter/`、
   `lib/facebetter.lib`、`lib/facebetter.dll`、`resource/resource.fbd`。
   当前工作区已准备此 SDK，目录由 Git 忽略；其他机器需要自行下载。
3. 复制 `windows/facebetter.local.cmake.example` 为 `windows/facebetter.local.cmake`。
   填入 `FACEBETTER_LICENSE_TOKEN`，或 `FACEBETTER_APP_ID` + `FACEBETTER_APP_KEY`。
   也可设置 `FACEBETTER_SDK_DIR` 指向其他解压目录。
4. 在装有 Flutter 和 Visual Studio C++ 工具链的机器执行 `flutter pub get`、
   `flutter build windows`。凭据变化后需重新构建。CMake 将 DLL 和基础模型复制进发行目录。

未提供 Windows ARM64 的 SDK 接入。没有 SDK 时可构建普通播放器，美颜状态显示缺少 SDK。
配置文件、下载的 SDK 均不进入 Git；打包进应用的凭据仍属于可提取的客户端凭据，
按厂商要求绑定实际应用标识。

## iOS

Podfile 固定 `Facebetter 2.1.1`，Swift 通过 Runner bridging header 使用实际 SDK API。
在共享 Aether wrapper 发布当前 AVPlayer 时绑定观察器，跟随 `currentItem` 更新，
通过 AVVideoComposition 的逐帧 Core Image 请求调用 SDK。音频和视频继续使用 AVPlayer
的时钟，输出保留给 AVPlayer / PiP。关闭或换片只移除本接入创建的 composition。
帧处理使用串行队列，输入/输出转换为 sRGB BGRA，输出复制到独立 CVPixelBuffer，
防止 SDK 重用输出内存。初始化成功前、授权失败或处理失败时输出原帧。

限制与 Windows 相同：SDR 1080p30 / 720p60。以下路径保留原画并显示状态：

- Aether 软件解码的 AVSampleBufferDisplayLayer 路径：上游目前未公开帧处理接口。
- 无法进行 AVVideoComposition 的素材（包括部分 HLS / 直播）。
- AirPlay 外部播放、已有其他 videoComposition 的素材。
- HDR / Dolby Vision / BT.2020、超限分辨率或帧率。

1. 复制 `ios/FacebetterConfig.plist.example` 为 `ios/FacebetterConfig.plist`。
2. 填入 `LICENSE_TOKEN`，或 `APP_ID` + `APP_KEY`，绑定最终 iOS bundle identifier。
3. 在 macOS 上执行 `flutter pub get`、`cd ios && pod install`，打开
   `Runner.xcworkspace` 构建。新增 Pod 尚未在当前 Windows 环境生成 Podfile.lock；
   首次安装会更新锁文件，CI 使用 `--deployment` 前须在 macOS 提交该更新。
4. Xcode 的构建阶段会将配置复制进应用；没有私有配置时使用空白示例，显示未配置授权。

不需要相机权限。此接入仅针对 iOS，没有给 tvOS 或 macOS 增加 SDK 依赖。

## 当前完成与未验证内容

已完成代码入口、平台依赖声明、运行时授权编辑与安全存储、配置模板、六项控制和状态回退逻辑。
已对照下载的 Windows / Apple 2.1.1 SDK 头文件核对调用方式。
当前机器没有 Flutter、MSVC 或 Xcode，尚未完成 Windows / iOS 应用构建，
也未用真实授权验证美颜、瘦脸、大眼、色彩、PiP 或目标设备帧率。
后续需分别在两端完成构建和实机验收，不能将代码接入视为效果已验证。

## GitHub Actions 打包

`Build All Platforms` 支持手动选择 Windows、Android（手机与 TV 矩阵）、iOS。
Windows 构建自动下载并校验 Facebetter 2.1.1 SDK，无需向 GitHub 提交 SDK 或授权。
Android 从 Maven 获取 SDK，iOS 从 CocoaPods 获取。授权通过安装后的设置页面填写。
发行模式 `release` 的 iOS 工件是未签名 IPA，需要自行签名安装；Android 没有仓库签名
密钥时使用调试签名。Windows 安装包没有配置签名服务时不签名。
Microsoft Store 包仅在勾选 `windows_store` 或标签构建时额外生成。
