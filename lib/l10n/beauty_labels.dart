import 'package:flutter/widgets.dart';

/// Localized labels for the fork's video beauty extension.
class BeautyLabels {
  BeautyLabels(String locale) : _zh = locale.startsWith('zh');
  factory BeautyLabels.of(BuildContext context) =>
      BeautyLabels(Localizations.localeOf(context).languageCode);

  final bool _zh;
  String get title => _zh ? '视频美颜' : 'Video beauty';
  String get enabled => _zh ? '开启美颜' : 'Enable beauty';
  String get smoothing => _zh ? '磨皮' : 'Smoothing';
  String get whitening => _zh ? '美白' : 'Whitening';
  String get rosiness => _zh ? '红润' : 'Rosiness';
  String get sharpening => _zh ? '锐化' : 'Sharpening';
  String get faceThin => _zh ? '瘦脸' : 'Slim face';
  String get eyeSize => _zh ? '大眼' : 'Larger eyes';
  String get licenseTitle => _zh ? '美颜授权' : 'Beauty license';
  String get licenseSaved => _zh ? '已保存本机授权' : 'License saved on this device';
  String get licenseEmpty =>
      _zh ? '配置当前平台的授权密钥' : 'Configure a license for this platform';
  String get licenseHelp => _zh
      ? '填写许可证 Token，或同时填写 App ID 和 App Key。授权须绑定当前应用标识，仅保存在本机，不随账号同步。保存后立即应用。'
      : 'Enter a license token, or both App ID and App Key. Bind the license to this app identifier. Credentials stay on this device and apply immediately after saving.';
  String get appIdentifier => _zh ? '应用标识' : 'App identifier';
  String get save => _zh ? '保存' : 'Save';
  String get clear => _zh ? '清除授权' : 'Clear license';
  String get cancel => _zh ? '取消' : 'Cancel';
  String get licenseIncomplete => _zh
      ? '请同时填写 App ID 和 App Key，或填写 Token'
      : 'Enter both App ID and App Key, or a token';
  String get licenseStorageFailed => _zh
      ? '无法访问本机安全存储，授权未保存，请重试'
      : 'Secure storage is unavailable. The license was not saved; please retry.';
  String get description => _zh
      ? '支持 Android、Windows、iOS 播放的 SDR 视频，最高 1080P/30fps 或 720P/60fps。超出范围保持原画。部分视频格式、直播和投屏不支持美颜。免费授权带水印，瘦脸和大眼需要对应套餐。'
      : 'For SDR video on Android, Windows and iOS, up to 1080p/30fps or 720p/60fps. Other video keeps the original picture. Some video formats, live streams and remote playback do not support beauty. Free licenses add a watermark; reshaping requires a supporting plan.';

  String status(String value) => switch (value) {
    'disabled' => _zh ? '已关闭，播放原画' : 'Off — original picture',
    'missingLicense' =>
      _zh ? '尚未配置授权，当前保持原画' : 'No license configured — original picture',
    'missingSdk' =>
      _zh ? '尚未安装美颜 SDK，当前保持原画' : 'Beauty SDK not installed — original picture',
    'missingResources' =>
      _zh ? '缺少美颜模型资源，当前保持原画' : 'Beauty resources missing — original picture',
    'bypassPlaybackPath' =>
      _zh
          ? '当前播放路径不支持美颜，保持原画'
          : 'Beauty unavailable on this playback path — original picture',
    'unsupportedDevice' =>
      _zh ? '当前设备不支持，保持原画' : 'Unsupported device — original picture',
    'initializing' => _zh ? '美颜引擎初始化中' : 'Initializing beauty engine',
    'ready' => _zh ? '美颜已生效' : 'Beauty active',
    'readyBasicOnly' => _zh ? '基础美颜已生效，当前授权不支持所选美型' : 'Skin effects active; selected reshape effects unavailable with this license',
    'bypassHdr' => _zh ? 'HDR 视频保持原画' : 'HDR video — original picture',
    'bypassResolution' =>
      _zh ? '超过 1080P，保持原画' : 'Above 1080p — original picture',
    'bypassFrameRate' =>
      _zh
          ? '超出支持的帧率，保持原画'
          : 'Frame rate exceeds supported limits — original picture',
    'failed' => _zh ? '美颜不可用，已回退原画；检查授权后重新开关美颜' : 'Beauty unavailable — original picture. Check the license and toggle beauty to retry.',
    _ => _zh ? '等待支持的视频播放' : 'Waiting for supported video playback',
  };
}
