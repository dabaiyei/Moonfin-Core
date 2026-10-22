# Android 视频美颜接入

## 在应用内配置授权（推荐）

进入 **设置 → 播放 → 视频美颜 → 美颜授权**，填写 License Token，或同时填写
App ID / App Key。页面显示当前平台和应用标识，用于在 Facebetter 控制台绑定授权。
Token / App Key 默认遮罩，数据存入当前设备的安全存储，不写入普通偏好、账号同步、
日志或 Git。Android 手机和 Android TV 各自保存授权。
保存后立即应用，已存在的美颜引擎会在帧处理线程重建；清除授权后保持原画。
若系统安全存储无法写入，页面显示失败，不会报告保存成功。

下文的构建时授权文件是可选预置方式。普通用户通过设置配置即可，无需重新打包。
本机保存的授权优先于预置值，清除操作也会覆盖预置授权。


本分支在 Moonfin 的 Android Media3 播放链路中接入 Facebetter 2.1.1。
可调参数：磨皮、美白、红润、锐化、瘦脸、大眼。默认关闭，参数保存在本机。

## 使用入口

- 设置 → 播放 → 播放器 → 视频美颜。
- Android Media3 视频播放时，控制栏中的人脸图标可打开调节面板。
- 电视遥控器上下切换选项，左右调节强度，每次 5%。

设置开关和参数会实时发送到原生播放器。无需暂停或重新打开视频。
如果在设置中切换了播放引擎，请使用 Media3；libmpv 和外部播放器没有接入此效果。

## 本地授权配置

1. 在 Facebetter 控制台创建 Android 应用，绑定最终 APK 包名。
   当前 `androidTv` 构建默认包名为 `org.moonfin.androidtv`，更改包名或使用测试后缀后需重新匹配授权。
2. 将 `android/facebetter.properties.example` 复制成 `android/facebetter.properties`。
3. 填入原生许可证 `FACEBETTER_LICENSE_TOKEN`，或填写在线授权的
   `FACEBETTER_APP_ID` 与 `FACEBETTER_APP_KEY`。三项也支持同名环境变量，环境变量优先。
4. 重新构建 APK。凭证写入原生构建配置，运行时不会同步到 Emby 用户偏好。

`facebetter.properties` 已被 Git 忽略。离线 `.lic` 需向供应商申请；可以将许可证全文写成
Java properties 单行值（换行使用 `\n`）。短时在线 token 会过期，不适合作为长期固定的发布凭证。
这里没有自动换取 token 的自建服务。如果需要面向用户公开发布，应接入自己的凭证服务。
打包的客户端不能保证嵌入密钥不可提取，优先采用绑定应用的许可证。

免费授权会显示供应商水印。瘦脸和大眼受套餐权限限制；权限不足时界面会明确提示，基础美颜继续工作。
未配置授权时不创建引擎，界面显示“尚未配置授权”，保持原画。

## 实现与范围

- Android 7.0/API 24 以上，ARM32/ARM64；Facebetter 没有提供 x86 原生库。
- `FacebetterEffect` 实现 Media3 `GlEffect`，在 GL 线程中创建引擎和逐帧处理纹理。
- Media3 传入线性 RGB：先转换到 sRGB 编码纹理供 SDK 处理，再转换回线性 RGB。
- SDK 输出帧在复制到 Media3 输出纹理后释放；上下文销毁时释放 SDK 与自有 GL 资源。
- 启用效果时禁用隧道播放；参数变化使用不可变快照，不重建播放器。
- 第一版支持 SDR，最高 1080P/30fps 或 720P/60fps。源信息已知的 HDR、杜比视界、
  更高分辨率或帧率会跳过美颜。实际 GL 输入为 HDR 或分辨率超限时也有二次保护。
- 预览、纯音频不应用美颜。授权失败、原生库加载失败或 SDK 处理失败时回退到原画，重新开关美颜可重试。
- 不新增相机或外部存储权限，不上传视频帧。

## 验收

新增的原生扩展已独立编译通过（使用 Android 36、Media3 1.10.1、Facebetter 2.1.1 的真实 API，
桥接与构建配置使用编译占位类），4 项 JVM 测试通过，覆盖 HDR/杜比视界、分辨率、帧率与非法参数。
这不等同于完整应用编译通过。

当前环境未找到 Flutter SDK，尚未完成整包构建与真机效果验证，也没有已配置的 Facebetter 授权。
需要在 ARM Android TV 上使用有效授权验证：六项参数、遥控器调节、开关、续播与换集、
HDR/4K 回退、授权失败回退、免费版水印，以及连续播放的帧率和温度。

参考：[Android 接入文档](https://docs.facebetter.net/zh/android/implement-beauty)、
[授权文档](https://docs.facebetter.net/zh/intro/license)、
[SDK 示例仓库](https://github.com/pixpark/facebetter-sdk)。
