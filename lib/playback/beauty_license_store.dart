import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../util/platform_detection.dart';

class BeautyLicense {
  const BeautyLicense({this.token = '', this.appId = '', this.appKey = ''});
  final String token;
  final String appId;
  final String appKey;
  bool get configured =>
      token.isNotEmpty || (appId.isNotEmpty && appKey.isNotEmpty);
  Map<String, String> toWire() => {
    'licenseToken': token,
    'appId': appId,
    'appKey': appKey,
  };
}

/// Credentials never enter synced preferences, diagnostics or source control.
class BeautyLicenseStore {
  static const _storage = FlutterSecureStorage();
  static Future<BeautyLicense?>? _loaded;
  static String get platform => PlatformDetection.isWindows
      ? 'Windows'
      : PlatformDetection.isIOS
      ? 'iOS'
      : PlatformDetection.isTV
      ? 'Android TV'
      : 'Android';
  static String get _key => 'moonfin.facebetter.license.v1.$platform';

  static Future<BeautyLicense?> load() => _loaded ??= _read();
  static Future<BeautyLicense?> _read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    final map = jsonDecode(value) as Map<String, dynamic>;
    return BeautyLicense(
      token: map['licenseToken'] as String? ?? '',
      appId: map['appId'] as String? ?? '',
      appKey: map['appKey'] as String? ?? '',
    );
  }

  static Future<void> save(BeautyLicense value) async {
    await _storage.write(key: _key, value: jsonEncode(value.toWire()));
    _loaded = Future.value(value);
  }
}
