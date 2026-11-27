import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 凭据存储：SESSDATA 这类等同于账号密码的 Cookie 不落明文普通文件。
///
/// iOS/macOS 走 Keychain，Android 走 Keystore 加密的 SharedPreferences。
class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _cookieKey = 'bilibili.cookies';

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> readCookies() async {
    try {
      final String? raw = await _storage.read(key: _cookieKey);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map(
          (String k, dynamic v) => MapEntry<String, String>(k, v.toString()),
        );
      }
    } catch (_) {
      // 密钥链不可用（例如未签名调试包）时退化为未登录，而不是崩溃。
    }
    return <String, String>{};
  }

  Future<void> writeCookies(Map<String, String> cookies) async {
    if (cookies.isEmpty) {
      await clear();
      return;
    }
    try {
      await _storage.write(key: _cookieKey, value: jsonEncode(cookies));
    } catch (_) {
      // 忽略写入失败，界面会保持未登录状态。
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _cookieKey);
    } catch (_) {
      // 同上。
    }
  }
}
