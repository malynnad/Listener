import 'package:dio/dio.dart';

import '../../core/config.dart';
import '../../models/radio_station.dart';

/// radio-browser.info 客户端。
///
/// 该项目要求：带可识别 UA、控制请求频率、标注数据来源。
/// 镜像通过官方 discovery 接口动态获取，失败时退回内置列表。
class RadioClient {
  RadioClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 18),
                headers: const <String, String>{
                  'User-Agent': AppConfig.userAgent,
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;
  String? _base;

  /// 上一次请求时间，用于把并发搜索压到 1 秒一次以内，避免被限流。
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _throttle() async {
    final int elapsed = DateTime.now().difference(_lastRequest).inMilliseconds;
    if (elapsed < 1000) {
      await Future<void>.delayed(Duration(milliseconds: 1000 - elapsed));
    }
    _lastRequest = DateTime.now();
  }

  Future<String> _ensureBase() async {
    final String? cached = _base;
    if (cached != null) return cached;

    final List<String> candidates = <String>[];
    try {
      final Response<dynamic> discovery =
          await _dio.get<dynamic>(AppConfig.radioDiscoveryUrl);
      final Object? data = discovery.data;
      if (data is List) {
        for (final dynamic item in data) {
          if (item is Map) {
            final String name = (item['name'] ?? '').toString();
            if (name.isNotEmpty && !name.startsWith('all.')) {
              candidates.add(name);
            }
          }
        }
      }
    } catch (_) {
      // 发现接口挂了就直接试兜底镜像。
    }
    candidates.addAll(AppConfig.radioFallbackMirrors);

    for (final String host in candidates.take(6)) {
      final String base = 'https://$host/json';
      try {
        final Response<dynamic> probe = await _dio.get<dynamic>(
          '$base/stats',
          options: Options(receiveTimeout: const Duration(seconds: 6)),
        );
        if (probe.statusCode == 200) {
          _base = base;
          return base;
        }
      } catch (_) {
        continue;
      }
    }
    throw const RadioException('电台服务暂时不可用，请检查网络后重试');
  }

  Future<List<RadioStation>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    await _throttle();
    final String base = await _ensureBase();
    try {
      final Response<dynamic> response =
          await _dio.get<dynamic>('$base$path', queryParameters: query);
      final Object? data = response.data;
      if (data is! List) return <RadioStation>[];
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> e) =>
              RadioStation.fromJson(e.cast<String, dynamic>()))
          .where((RadioStation s) => s.url.isNotEmpty && s.name.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      // 镜像失效时清空缓存，下次请求重新发现。
      _base = null;
      throw RadioException('拉取电台列表失败：${e.message ?? e.type.name}');
    }
  }

  Future<List<RadioStation>> topHits({int limit = 100}) {
    return _getList(
      '/stations/topclick/$limit',
      query: <String, String>{'hidebroken': 'true'},
    );
  }

  Future<List<RadioStation>> search(String keyword, {int limit = 60}) {
    return _getList(
      '/stations/search',
      query: <String, String>{
        'name': keyword,
        'limit': '$limit',
        'hidebroken': 'true',
        'order': 'clickcount',
        'reverse': 'true',
      },
    );
  }

  Future<List<RadioStation>> byCountry(String code, {int limit = 80}) {
    return _getList(
      '/stations/bycountrycodeexact/$code',
      query: <String, String>{
        'limit': '$limit',
        'hidebroken': 'true',
        'order': 'clickcount',
        'reverse': 'true',
      },
    );
  }

  /// 返回 [国家代码, 中文/英文国家名] 列表，按名称排序。
  Future<List<MapEntry<String, String>>> countries() async {
    await _throttle();
    final String base = await _ensureBase();
    try {
      final Response<dynamic> response = await _dio.get<dynamic>('$base/countries');
      final Object? data = response.data;
      final List<MapEntry<String, String>> result = <MapEntry<String, String>>[];
      if (data is List) {
        for (final dynamic item in data) {
          if (item is! Map) continue;
          final String code = (item['iso_3166_1'] ?? '').toString();
          final String name = (item['name'] ?? '').toString();
          final int count = (item['stationcount'] as num?)?.toInt() ?? 0;
          if (code.isEmpty || count < 20) continue;
          result.add(MapEntry<String, String>(code, '$name ($code)'));
        }
      }
      result.sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.key.compareTo(b.key));
      return result;
    } on DioException {
      return <MapEntry<String, String>>[];
    }
  }
}

class RadioException implements Exception {
  const RadioException(this.message);

  final String message;

  @override
  String toString() => message;
}
