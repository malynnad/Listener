/// 应用级常量。集中放置，避免散落在各处。
class AppConfig {
  AppConfig._();

  static const String appName = 'Listener';
  static const String version = '0.1.2';

  /// radio-browser.info 要求客户端带可识别的 UA，便于他们统计与联系。
  static const String userAgent =
      'Listener/$version (+https://github.com/mallynad/Listener)';

  /// B 站接口要求的浏览器 UA，缺省会被 403。
  static const String browserUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  /// radio-browser.info 官方入口，用于发现当前可用镜像。
  static const String radioDiscoveryUrl =
      'https://all.api.radio-browser.info/json/servers';

  /// 镜像发现失败时的兜底列表，按顺序尝试。
  static const List<String> radioFallbackMirrors = <String>[
    'de1.api.radio-browser.info',
    'de2.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'at1.api.radio-browser.info',
    'fi1.api.radio-browser.info',
  ];

  /// 支持的本地音频扩展名。
  static const Set<String> audioExtensions = <String>{
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
    '.ape',
    '.alac',
    '.aiff',
  };

  /// B 站音轨的请求头，缺 Referer 会 403。
  static const Map<String, String> biliMediaHeaders = <String, String>{
    'Referer': 'https://www.bilibili.com',
    'User-Agent': browserUserAgent,
    'Origin': 'https://www.bilibili.com',
  };

  /// Android 上待扫描的音乐目录。
  ///
  /// 分区存储下无法枚举整块外部存储，因此固定扫描这几个约定目录：
  /// 系统媒体库目录 + 主流播放器的下载目录。不存在的会被跳过。
  static const List<String> androidMusicRoots = <String>[
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Podcasts',
    '/storage/emulated/0/Ringtones',
    // 网易云音乐
    '/storage/emulated/0/netease/cloudmusic/Music',
    // QQ 音乐
    '/storage/emulated/0/qqmusic/song',
    // 酷狗
    '/storage/emulated/0/kgmusic/download',
  ];

  /// 扫描时跳过的路径片段：系统目录体积大且不含用户音乐。
  static const List<String> scanSkipSegments = <String>[
    '/Android/',
    '/.thumbnails/',
    '/MIUI/.cache/',
  ];

  /// 本应用自己的外部目录片段，与 `applicationId` 保持一致。
  ///
  /// B 站音轨下载落在 `/Android/data/<包名>/files/downloads`，会被上面的
  /// `/Android/` 规则误伤。这里单独放行，让下载完的曲子能出现在本地库里。
  static const String ownDataSegment = '/com.listener.player/';
}
