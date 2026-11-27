import 'package:flutter_test/flutter_test.dart';
import 'package:listener/features/bilibili/bili_client.dart';
import 'package:listener/features/bilibili/wbi.dart';

void main() {
  group('WBI 签名', () {
    test('mixinKey 与公开测试向量一致', () {
      final String key = mixinKeyFromUrls(
        'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
        'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
      );
      expect(key, 'ea1db124af3c7062474693fa704f4ff8');
    });

    test('签名包含 wts 与 32 位 w_rid，且保留原始参数值', () {
      final Map<String, String> signed = signWbi(
        <String, String>{'foo': '114', 'bar': '514', 'zab': "1!'()*"},
        'ea1db124af3c7062474693fa704f4ff8',
        timestampSeconds: 1702204169,
      );
      expect(signed['wts'], '1702204169');
      expect(signed['zab'], "1!'()*");
      expect(signed['w_rid'], hasLength(32));
      expect(signed['w_rid'], matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('key 不完整时抛 ArgumentError', () {
      expect(
        () => mixinKeyFromUrls('https://x/a.png', 'https://x/b.png'),
        throwsArgumentError,
      );
    });

    test('查询串用 %20 编码空格，且键按字典序排列', () {
      final String query = buildSignedQuery(<String, String>{
        'keyword': '周杰伦 晴天',
        'wts': '1702204169',
      });
      expect(query.contains('%20'), isTrue);
      expect(query.contains('+'), isFalse);
      expect(query.startsWith('keyword='), isTrue);
    });
  });

  group('搜索标题清洗', () {
    test('去掉 em 高亮标签并解码实体', () {
      expect(stripHtml('<em class="keyword">晴天</em> &amp; 雨天'), '晴天 & 雨天');
    });
  });
}
