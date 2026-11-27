import 'dart:convert';

import 'package:crypto/crypto.dart';

/// WBI 签名算法的纯函数实现（无 IO，可直接单测）。
///
/// B 站自 2023 年起对 `wbi/` 前缀的接口要求签名：
/// 取 nav 接口返回的 img_key + sub_key，按固定表重排后取前 32 位作为 mixinKey，
/// 再把排序后的 query 串拼上 mixinKey 做 MD5 得到 `w_rid`。
const List<int> _mixinKeyEncTab = <int>[
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
  37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
  22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
];

/// 从 nav 接口返回的两个 key URL 中截取文件名，再重排出 mixinKey。
String mixinKeyFromUrls(String imgUrl, String subUrl) {
  final String imgKey = _fileName(imgUrl);
  final String subKey = _fileName(subUrl);
  if (imgKey.length + subKey.length < 64) {
    throw ArgumentError('wbi key 不完整：img=${imgKey.length} sub=${subKey.length}');
  }
  final String raw = '$imgKey$subKey';
  final StringBuffer sb = StringBuffer();
  for (final int i in _mixinKeyEncTab) {
    sb.write(raw[i]);
  }
  return sb.toString().substring(0, 32);
}

String _fileName(String url) {
  final String last = url.split('/').last;
  final int dot = last.indexOf('.');
  return dot == -1 ? last : last.substring(0, dot);
}

/// 返回带 `wts` 与 `w_rid` 的参数表。
///
/// 注意：`Uri.encodeComponent` 把空格编成 `%20`，与前端 `encodeURIComponent` 一致；
/// 用 `encodeQueryComponent` 会编成 `+`，B 站会判定签名错误。
Map<String, String> signWbi(
  Map<String, String> params,
  String mixinKey, {
  int? timestampSeconds,
}) {
  final Map<String, String> signed = Map<String, String>.from(params);
  signed['wts'] = (timestampSeconds ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000)
      .toString();
  final List<String> keys = signed.keys.toList()..sort();
  final String query = keys.map((String key) {
    final String value =
        signed[key]!.replaceAll(RegExp(r"[!'()*]"), '');
    return '${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}';
  }).join('&');
  final String rid =
      md5.convert(utf8.encode('$query$mixinKey')).toString();
  return <String, String>{...signed, 'w_rid': rid};
}

/// 把已签名参数拼成可直接塞进 URL 的查询串。
///
/// 必须与签名使用同一套编码（`Uri.encodeComponent`，空格编成 `%20`）。
/// 若改用 Dio 的 `queryParameters`，Dio 会把空格编成 `+`，
/// 服务端重算签名时得到的串与 `w_rid` 不一致，请求会被拒。
String buildSignedQuery(Map<String, String> signedParams) {
  final List<String> keys = signedParams.keys.toList()..sort();
  return keys
      .map((String key) =>
          '${Uri.encodeComponent(key)}=${Uri.encodeComponent(signedParams[key]!)}')
      .join('&');
}

/// 供测试使用：暴露 md5，避免测试里重复引入 crypto。
String md5Of(String input) => md5.convert(utf8.encode(input)).toString();
