import 'package:dio/dio.dart';

import '../../core/config.dart';
import 'bili_models.dart';
import 'wbi.dart';

/// B 站 Web 接口客户端。
///
/// 所有请求都带浏览器 UA + Referer：B 站对 `api.bilibili.com` 的部分接口
/// 会校验来源，裸请求容易直接吃 -412。
class BiliClient {
  BiliClient({
    required Map<String, String> Function() cookieProvider,
    Dio? dio,
  })  : _cookieProvider = cookieProvider,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                headers: const <String, String>{
                  'User-Agent': AppConfig.browserUserAgent,
                  'Referer': 'https://www.bilibili.com',
                  'Origin': 'https://www.bilibili.com',
                  'Accept': 'application/json, text/plain, */*',
                  'Accept-Language': 'zh-CN,zh;q=0.9',
                },
              ),
            );

  final Map<String, String> Function() _cookieProvider;
  final Dio _dio;

  String? _mixinKey;
  DateTime? _mixinKeyAt;

  String get _cookieHeader => _cookieProvider()
      .entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('; ');

  Map<String, String> get _commonHeaders {
    final String cookie = _cookieHeader;
    return <String, String>{
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  Future<Map<String, dynamic>> _request(
    String url, {
    Map<String, String>? query,
    String? rawQuery,
  }) async {
    final bool useRaw = rawQuery != null && rawQuery.isNotEmpty;
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        useRaw ? '$url?$rawQuery' : url,
        queryParameters: useRaw ? null : query,
        options: Options(headers: _commonHeaders),
      );
      final dynamic body = response.data;
      if (body is Map<String, dynamic>) return body;
      if (body is Map) return body.cast<String, dynamic>();
      throw BiliException(-1, '响应格式异常');
    } on DioException catch (e) {
      final int status = e.response?.statusCode ?? 0;
      if (status == 412) throw BiliException(-412, '请求被拦截');
      if (status == 403) throw BiliException(403, '无权访问');
      if (status > 0) throw BiliException(status, e.message ?? 'HTTP $status');
      throw BiliException(-1, '网络错误：${e.message ?? e.type.name}');
    }
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final int code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw BiliException(code, (body['message'] ?? body['msg'] ?? '').toString());
    }
    final dynamic data = body['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// 取出 data 字段，但不因业务码非 0 就抛错。
  ///
  /// nav 接口在未登录时返回 `code=-101`，可 `data.wbi_img` 依然有效，
  /// 因此取签名密钥和判断登录态都不能走 [_unwrap]。
  Map<String, dynamic> _dataOf(Map<String, dynamic> body) {
    final dynamic data = body['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// 获取（并缓存）WBI mixinKey。nav 接口同时提供 key 与登录态。
  Future<Map<String, dynamic>> _navRaw() =>
      _request('https://api.bilibili.com/x/web-interface/nav');

  Future<String> _mixin() async {
    final String? cached = _mixinKey;
    final DateTime? at = _mixinKeyAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 30)) {
      return cached;
    }
    final Map<String, dynamic> nav = _dataOf(await _navRaw());
    final Map<String, dynamic>? wbi =
        (nav['wbi_img'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
    final String? img = wbi?['img_url'] as String?;
    final String? sub = wbi?['sub_url'] as String?;
    if (img == null || sub == null) {
      throw BiliException(-1, '未能获取 WBI 签名密钥，请检查网络');
    }
    _mixinKey = mixinKeyFromUrls(img, sub);
    _mixinKeyAt = DateTime.now();
    return _mixinKey!;
  }

  /// 当前登录用户；未登录返回 null。
  ///
  /// 未登录时 nav 返回 -101，这是正常状态而非错误，不能当异常抛给界面。
  Future<BiliUser?> fetchUser() async {
    final Map<String, dynamic> nav = _dataOf(await _navRaw());
    if (nav['isLogin'] != true) return null;
    final String? face = _normalizeUrl(nav['face'] as String?);
    return BiliUser(
      mid: (nav['mid'] as num?)?.toInt() ?? 0,
      name: (nav['uname'] ?? '').toString(),
      face: face,
      vip: (nav['vipStatus'] as num?)?.toInt() == 1,
    );
  }

  /// 视频搜索。`search/type` 属于 wbi 接口，未签名会返回 -403。
  Future<List<BiliSearchResult>> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final String mixin = await _mixin();
    final Map<String, String> signed = signWbi(
      <String, String>{
        'search_type': 'video',
        'keyword': keyword,
        'page': '$page',
        'page_size': '$pageSize',
      },
      mixin,
    );
    final Map<String, dynamic> data = _unwrap(await _request(
      'https://api.bilibili.com/x/web-interface/wbi/search/type',
      rawQuery: buildSignedQuery(signed),
    ));
    final List<dynamic> items =
        data['result'] as List<dynamic>? ?? <dynamic>[];
    final List<BiliSearchResult> results = <BiliSearchResult>[];
    for (final dynamic raw in items) {
      if (raw is! Map) continue;
      final Map<String, dynamic> item = raw.cast<String, dynamic>();
      final String bvid = (item['bvid'] ?? '').toString();
      if (bvid.isEmpty) continue;
      results.add(BiliSearchResult(
        bvid: bvid,
        title: stripHtml((item['title'] ?? '').toString()),
        author: stripHtml((item['author'] ?? '').toString()),
        cover: _normalizeUrl(item['pic']?.toString()),
        duration: _parseDuration(item['duration']?.toString()),
        playCount: (item['play'] as num?)?.toInt() ?? 0,
        pubdate: item['pubdate'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (item['pubdate'] as num).toInt() * 1000)
            : null,
      ));
    }
    return results;
  }

  /// 解析可播放音轨。优先 DASH 音频流；失败时退回 MP4 直链。
  Future<BiliVideoInfo> resolveAudio(String bvid) async {
    final Map<String, dynamic> view = _unwrap(await _request(
      'https://api.bilibili.com/x/web-interface/view',
      query: <String, String>{'bvid': bvid},
    ));
    final int cid =
        (view['cid'] as num?)?.toInt() ?? _firstPageCid(view) ?? 0;
    if (cid == 0) throw BiliException(-404, '该视频没有可播放的分P');

    final String mixin = await _mixin();
    final Map<String, String> signed = signWbi(
      <String, String>{
        'bvid': bvid,
        'cid': '$cid',
        'fnval': '16',
        'fnver': '0',
        'fourk': '1',
      },
      mixin,
    );
    final Map<String, dynamic> play = _unwrap(await _request(
      'https://api.bilibili.com/x/player/wbi/playurl',
      rawQuery: buildSignedQuery(signed),
    ));

    final List<BiliAudioStream> streams = <BiliAudioStream>[];
    final Map<String, dynamic>? dash =
        (play['dash'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
    if (dash != null) {
      final Map<String, dynamic>? flac =
          (dash['flac'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
      final Map<String, dynamic>? flacAudio =
          (flac?['audio'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
      if (flacAudio != null) {
        final BiliAudioStream? s = _streamOf(flacAudio, 'Hi-Res FLAC');
        if (s != null) streams.add(s);
      }
      final Map<String, dynamic>? dolby =
          (dash['dolby'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
      final List<dynamic> dolbyAudio =
          dolby?['audio'] as List<dynamic>? ?? <dynamic>[];
      for (final dynamic item in dolbyAudio) {
        if (item is Map) {
          final BiliAudioStream? s =
              _streamOf(item.cast<String, dynamic>(), 'Dolby Atmos');
          if (s != null) streams.add(s);
        }
      }
      final List<dynamic> audios =
          dash['audio'] as List<dynamic>? ?? <dynamic>[];
      for (final dynamic item in audios) {
        if (item is! Map) continue;
        final Map<String, dynamic> audio = item.cast<String, dynamic>();
        final BiliAudioStream? s = _streamOf(
          audio,
          _audioQualityLabel((audio['id'] as num?)?.toInt()),
        );
        if (s != null) streams.add(s);
      }
    }

    if (streams.isEmpty) {
      final List<dynamic> durl = play['durl'] as List<dynamic>? ?? <dynamic>[];
      for (final dynamic item in durl) {
        if (item is! Map) continue;
        final String? url = (item['url'] ?? item['base_url'])?.toString();
        if (url != null && url.isNotEmpty) {
          streams.add(BiliAudioStream(url: url, label: 'MP4 音轨'));
        }
      }
    }
    streams.sort((BiliAudioStream a, BiliAudioStream b) =>
        (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0));

    if (streams.isEmpty) {
      throw BiliException(-404, '未取到音轨，可能是付费/大会员专享内容');
    }

    return BiliVideoInfo(
      bvid: bvid,
      cid: cid,
      title: stripHtml((view['title'] ?? '').toString()),
      owner: stripHtml(
          ((view['owner'] as Map<dynamic, dynamic>?)?['name'] ?? '').toString()),
      duration: Duration(seconds: (view['duration'] as num?)?.toInt() ?? 0),
      streams: streams,
      cover: _normalizeUrl(view['pic']?.toString()),
    );
  }

  BiliAudioStream? _streamOf(Map<String, dynamic> json, String label) {
    final String url =
        (json['baseUrl'] ?? json['base_url'] ?? json['url'] ?? '').toString();
    if (url.isEmpty) return null;
    final List<dynamic> backup =
        json['backupUrl'] as List<dynamic>? ??
            json['backup_url'] as List<dynamic>? ??
            <dynamic>[];
    return BiliAudioStream(
      url: url,
      label: label,
      backupUrls: backup.map((dynamic e) => e.toString()).toList(),
      bandwidth: (json['bandwidth'] as num?)?.toInt(),
    );
  }

  int? _firstPageCid(Map<String, dynamic> view) {
    final List<dynamic> pages = view['pages'] as List<dynamic>? ?? <dynamic>[];
    if (pages.isEmpty) return null;
    final dynamic first = pages.first;
    if (first is Map) return (first['cid'] as num?)?.toInt();
    return null;
  }

  static String _audioQualityLabel(int? id) {
    switch (id) {
      case 30216:
        return '64K';
      case 30232:
        return '132K';
      case 30280:
        return '192K';
      case 30250:
        return 'Dolby';
      case 30251:
        return 'Hi-Res';
      default:
        return '音轨';
    }
  }

  static String? _normalizeUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('//')) return 'https:$raw';
    return raw;
  }

  static Duration _parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return Duration.zero;
    final List<String> parts = raw.split(':');
    int seconds = 0;
    for (final String part in parts) {
      seconds = seconds * 60 + (int.tryParse(part) ?? 0);
    }
    return Duration(seconds: seconds);
  }
}

/// 搜索结果的标题带 `<em class="keyword">` 高亮标签，必须清掉才能显示。
String stripHtml(String input) {
  if (input.isEmpty) return input;
  return input
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}
