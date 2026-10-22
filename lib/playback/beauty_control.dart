import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../preference/user_preferences.dart';
import '../util/platform_detection.dart';
import 'beauty_license_store.dart';

/// Shares status between the settings page and the currently playing video.
/// License values come from device secure storage, outside user preferences.
class BeautyControl {
  BeautyControl._();

  static MethodChannel get _channel => MethodChannel(
    PlatformDetection.isAndroid
        ? 'moonfin/media3_video_control'
        : 'moonfin/beauty_control',
  );
  static bool get supported =>
      PlatformDetection.isAndroid ||
      PlatformDetection.isWindows ||
      PlatformDetection.isIOS;
  static int? windowsHandle;
  static String windowsBypassStatus = '';
  static bool windowsConfigured = false;
  static final configurationChanged = ValueNotifier<int>(0);
  static final status = ValueNotifier<String>('waiting');

  static Map<String, dynamic> payload(UserPreferences prefs) => {
    'enabled': prefs.get(UserPreferences.beautyEnabled),
    if (PlatformDetection.isWindows) 'handle': windowsHandle ?? 0,
    if (PlatformDetection.isWindows) 'bypassStatus': windowsBypassStatus,
    'smoothing': prefs.get(UserPreferences.beautySmoothing).clamp(0, 100) / 100,
    'whitening': prefs.get(UserPreferences.beautyWhitening).clamp(0, 100) / 100,
    'rosiness': prefs.get(UserPreferences.beautyRosiness).clamp(0, 100) / 100,
    'sharpening':
        prefs.get(UserPreferences.beautySharpening).clamp(0, 100) / 100,
    'faceThin': prefs.get(UserPreferences.beautyFaceThin).clamp(0, 100) / 100,
    'eyeSize': prefs.get(UserPreferences.beautyEyeSize).clamp(0, 100) / 100,
  };

  static void acceptStatus(Map<dynamic, dynamic> event) {
    final value = event['status'];
    if (value is String) status.value = value;
  }

  static Future<void> refreshStatus() async {
    if (!supported) return;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getBeautyStatus',
      );
      if (result != null) acceptStatus(result);
    } on PlatformException {
      status.value = 'failed';
    } on MissingPluginException {
      status.value = 'unsupportedDevice';
    }
  }

  static Future<void> apply(UserPreferences prefs) async {
    if (!supported) return;
    try {
      final license = await BeautyLicenseStore.load();
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setBeautyPreferences',
        {...payload(prefs), if (license != null) 'license': license.toWire()},
      );
      if (result != null) {
        if (PlatformDetection.isWindows) {
          final configured = result['configured'] == true;
          if (windowsConfigured != configured) {
            windowsConfigured = configured;
            configurationChanged.value++;
          }
        }
        acceptStatus(result);
      }
    } on PlatformException {
      status.value = 'failed';
    } on MissingPluginException {
      status.value = 'unsupportedDevice';
    } on FormatException {
      status.value = 'failed';
    }
  }
}
