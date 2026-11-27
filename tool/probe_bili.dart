// 端到端自检：验证 WBI 签名链路在真实接口上可用。
//
// 运行：dart run tool/probe_bili.dart [关键词]
//
// 不依赖 Flutter，只用 dart:io，因此可在纯 Dart 环境直接跑。
// 用途：当 B 站返回 -352 / -403 时，先跑这个脚本判断是签名错了还是风控了。
import 'dart:convert';
import 'dart:io';

import 'package:listener/features/bilibili/wbi.dart';

const String _ua =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

final HttpClient _client = HttpClient();

Future<Map<String, dynamic>> _get(String url) async {
  final HttpClientRequest req = await _client.getUrl(Uri.parse(url));
  req.headers
    ..set(HttpHeaders.userAgentHeader, _ua)
    ..set(HttpHeaders.refererHeader, 'https://www.bilibili.com');
  final HttpClientResponse res = await req.close();
  final String body = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    throw StateError('HTTP ${res.statusCode}: ${body.substring(0, 120)}');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<void> main(List<String> args) async {
  final String keyword = args.isEmpty ? '周杰伦' : args.first;

  // 1. nav 取 wbi key（未登录也会返回 key，code=-101 属正常）
  final Map<String, dynamic> nav = await _get(
    'https://api.bilibili.com/x/web-interface/nav',
  );
  final Map<String, dynamic> wbi =
      (nav['data'] as Map<String, dynamic>)['wbi_img'] as Map<String, dynamic>;
  final String mixin = mixinKeyFromUrls(
    wbi['img_url'] as String,
    wbi['sub_url'] as String,
  );
  stdout.writeln('[1] mixinKey = $mixin');

  // 2. 签名搜索
  final Map<String, String> signed = signWbi(<String, String>{
    'search_type': 'video',
    'keyword': keyword,
    'page': '1',
    'page_size': '5',
  }, mixin);
  final Map<String, dynamic> search = await _get(
    'https://api.bilibili.com/x/web-interface/wbi/search/type'
    '?${buildSignedQuery(signed)}',
  );
  stdout.writeln('[2] search code=${search['code']} msg=${search['message']}');
  if (search['code'] != 0) {
    stderr.writeln('搜索失败，签名或风控异常');
    exit(1);
  }

  final List<dynamic> videos =
      ((search['data'] as Map<String, dynamic>)['result'] as List<dynamic>?) ??
          <dynamic>[];
  if (videos.isEmpty) {
    stderr.writeln('搜索结果为空');
    exit(1);
  }

  for (final dynamic raw in videos.take(3)) {
    final Map<String, dynamic> v = raw as Map<String, dynamic>;
    final String title = (v['title'] as String)
        .replaceAll(RegExp(r'</?em[^>]*>'), '')
        .replaceAll('&quot;', '"');
    stdout.writeln('    ${v['bvid']}  ${v['author']}  $title');
  }

  // 3. 取 cid → 取音轨
  final Map<String, dynamic> first = videos.first as Map<String, dynamic>;
  final String bvid = first['bvid'] as String;
  final Map<String, dynamic> pages = await _get(
    'https://api.bilibili.com/x/player/pagelist?bvid=$bvid',
  );
  final int cid = ((pages['data'] as List<dynamic>).first
      as Map<String, dynamic>)['cid'] as int;
  stdout.writeln('[3] bvid=$bvid cid=$cid');

  final Map<String, String> playSigned = signWbi(<String, String>{
    'bvid': bvid,
    'cid': '$cid',
    'fnval': '16',
    'fnver': '0',
    'fourk': '1',
  }, mixin);
  final Map<String, dynamic> play = await _get(
    'https://api.bilibili.com/x/player/wbi/playurl'
    '?${buildSignedQuery(playSigned)}',
  );
  stdout.writeln('[4] playurl code=${play['code']} msg=${play['message']}');
  if (play['code'] != 0) {
    stderr.writeln('取音轨失败');
    exit(1);
  }

  final Map<String, dynamic> dash =
      (play['data'] as Map<String, dynamic>)['dash'] as Map<String, dynamic>? ??
          <String, dynamic>{};
  final List<dynamic> audios = (dash['audio'] as List<dynamic>?) ?? <dynamic>[];
  if (audios.isEmpty) {
    stderr.writeln('未返回 DASH 音轨');
    exit(1);
  }
  for (final dynamic raw in audios) {
    final Map<String, dynamic> a = raw as Map<String, dynamic>;
    stdout.writeln(
      '    audio id=${a['id']} codec=${a['codecs']} '
      '${a['bandwidth']}bps  可播=${(a['baseUrl'] as String).isNotEmpty}',
    );
  }
  stdout.writeln('全部通过');
  _client.close();
}
