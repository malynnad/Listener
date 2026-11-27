/// B 站相关的数据模型与异常。
class BiliUser {
  const BiliUser({
    required this.mid,
    required this.name,
    this.face,
    this.vip = false,
  });

  final int mid;
  final String name;
  final String? face;
  final bool vip;
}

class BiliSearchResult {
  const BiliSearchResult({
    required this.bvid,
    required this.title,
    required this.author,
    required this.cover,
    required this.duration,
    required this.playCount,
    this.pubdate,
  });

  final String bvid;
  final String title;
  final String author;
  final String? cover;
  final Duration duration;
  final int playCount;
  final DateTime? pubdate;

  String get durationText {
    final int total = duration.inSeconds;
    final String mm = (total ~/ 60).toString().padLeft(2, '0');
    final String ss = (total % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

/// 一条可播放的音轨（DASH 音频流或 MP4 回退流）。
class BiliAudioStream {
  const BiliAudioStream({
    required this.url,
    required this.label,
    this.backupUrls = const <String>[],
    this.bandwidth,
  });

  final String url;
  final String label;
  final List<String> backupUrls;
  final int? bandwidth;
}

class BiliVideoInfo {
  const BiliVideoInfo({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.owner,
    required this.duration,
    required this.streams,
    this.cover,
  });

  final String bvid;
  final int cid;
  final String title;
  final String owner;
  final Duration duration;
  final List<BiliAudioStream> streams;
  final String? cover;

  BiliAudioStream? get best => streams.isEmpty ? null : streams.first;
}

class BiliException implements Exception {
  BiliException(this.code, this.message);

  final int code;
  final String message;

  String get friendly {
    switch (code) {
      case -101:
        return '登录状态已失效，请重新扫码登录';
      case -352:
        return '触发风控（-352），请稍后再试或降低请求频率';
      case -412:
        return '请求被拦截（-412），请稍后再试';
      case -400:
        return '请求参数有误（-400）';
      case -404:
        return '内容不存在或已下架';
      default:
        return '接口错误 $code：$message';
    }
  }

  @override
  String toString() => friendly;
}

class QrChallenge {
  const QrChallenge({required this.url, required this.key});

  final String url;
  final String key;
}

enum QrPollStatus { waiting, scanned, expired, success, failure }

class QrPollResult {
  const QrPollResult(this.status, {this.message});

  final QrPollStatus status;
  final String? message;
}
