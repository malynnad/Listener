import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../core/credential_store.dart';
import 'bili_models.dart';

/// 扫码登录。
///
/// 走 passport 的 web 二维码流程而不是内嵌 WebView：桌面端不必处理
/// WKWebView 的 Cookie 同步问题，Android 端也少一个 WebView 依赖。
class BiliAuthService extends ChangeNotifier {
  BiliAuthService({CredentialStore? store, Dio? dio})
      : _store = store ?? CredentialStore(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: const <String, String>{
                  'User-Agent': AppConfig.browserUserAgent,
                  'Referer': 'https://www.bilibili.com',
                  'Origin': 'https://www.bilibili.com',
                },
              ),
            );

  final CredentialStore _store;
  final Dio _dio;

  Map<String, String> _cookies = <String, String>{};
  bool _restoring = true;

  Map<String, String> get cookies => Map<String, String>.unmodifiable(_cookies);
  bool get restoring => _restoring;
  bool get isLoggedIn => _cookies.containsKey('SESSDATA');

  Future<void> restore() async {
    _cookies = await _store.readCookies();
    _restoring = false;
    notifyListeners();
  }

  Future<QrChallenge> createQr() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
    );
    final Map<String, dynamic> body = _asMap(response.data);
    if ((body['code'] as num?)?.toInt() != 0) {
      throw BiliException(
        (body['code'] as num?)?.toInt() ?? -1,
        (body['message'] ?? '二维码生成失败').toString(),
      );
    }
    final Map<String, dynamic> data = _asMap(body['data']);
    final String url = (data['url'] ?? '').toString();
    final String key = (data['qrcode_key'] ?? '').toString();
    if (url.isEmpty || key.isEmpty) {
      throw BiliException(-1, '二维码数据为空');
    }
    return QrChallenge(url: url, key: key);
  }

  Future<QrPollResult> pollQr(String key) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
      queryParameters: <String, String>{'qrcode_key': key},
      options: Options(validateStatus: (int? status) => status != null && status < 500),
    );
    final Map<String, dynamic> body = _asMap(response.data);
    if ((body['code'] as num?)?.toInt() != 0) {
      return QrPollResult(
        QrPollStatus.failure,
        message: (body['message'] ?? '轮询失败').toString(),
      );
    }
    final Map<String, dynamic> data = _asMap(body['data']);
    final int code = (data['code'] as num?)?.toInt() ?? -1;
    switch (code) {
      case 0:
        _harvest(response, data);
        if (!isLoggedIn) {
          return const QrPollResult(
            QrPollStatus.failure,
            message: '登录成功但未取到 Cookie，请重试',
          );
        }
        await _store.writeCookies(_cookies);
        notifyListeners();
        return const QrPollResult(QrPollStatus.success);
      case 86101:
        return const QrPollResult(QrPollStatus.waiting);
      case 86090:
        return const QrPollResult(QrPollStatus.scanned);
      case 86038:
        return const QrPollResult(QrPollStatus.expired);
      default:
        return QrPollResult(
          QrPollStatus.failure,
          message: '未知状态 $code',
        );
    }
  }

  /// Cookie 有两个来源，缺一不可：
  /// 1. `Set-Cookie` 响应头（httpOnly 项只能从这里拿）
  /// 2. 返回体里的跳转 url 查询串（部分环境不带 Set-Cookie）
  void _harvest(Response<dynamic> response, Map<String, dynamic> data) {
    final Map<String, List<String>> headers = response.headers.map;
    final List<String>? rawCookies =
        headers['set-cookie'] ?? headers['Set-Cookie'];
    if (rawCookies != null) {
      for (final String raw in rawCookies) {
        final String first = raw.split(';').first.trim();
        final int eq = first.indexOf('=');
        if (eq > 0) {
          _cookies[first.substring(0, eq)] = first.substring(eq + 1);
        }
      }
    }

    final String jump = (data['url'] ?? '').toString();
    if (jump.isEmpty) return;
    final Uri? uri = Uri.tryParse(jump);
    if (uri == null) return;
    const Set<String> wanted = <String>{
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
      'sid',
    };
    // 不做 URL 解码：Cookie 值本身是百分号编码的，解码后发出去反而对不上。
    for (final String pair in uri.query.split('&')) {
      final int eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final String name = pair.substring(0, eq);
      if (!wanted.contains(name)) continue;
      _cookies[name] = pair.substring(eq + 1);
    }
  }

  Future<void> logout() async {
    _cookies = <String, String>{};
    await _store.clear();
    notifyListeners();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return <String, dynamic>{};
  }
}
