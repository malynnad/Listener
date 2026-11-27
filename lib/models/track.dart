enum TrackSource { local, bilibili, radio }

/// 播放队列中的统一曲目模型。
///
/// 三个来源（本地文件 / B 站音轨 / 网络电台）都收敛成这一个结构，
/// 播放内核无需关心来源差异，只需把 [uri] 和 [headers] 交给 mpv。
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.uri,
    required this.source,
    this.artist,
    this.album,
    this.headers,
    this.artwork,
    this.duration,
    this.downloadUrl,
    this.extra,
  });

  final String id;
  final String title;
  final String uri;
  final TrackSource source;
  final String? artist;
  final String? album;

  /// 打开媒体时需要附带的 HTTP 头（B 站 Referer / 电台 UA）。
  final Map<String, String>? headers;

  /// 封面：本地路径或网络 URL，二者靠 [artworkIsLocal] 区分。
  final String? artwork;
  final Duration? duration;

  /// B 站音轨的原始直链，用于下载。
  final String? downloadUrl;

  /// 来源附加信息，例如清晰度、码率、up 主。
  final String? extra;

  bool get artworkIsLocal =>
      artwork != null && artwork!.startsWith('/');

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? artwork,
    Duration? duration,
  }) {
    return Track(
      id: id,
      title: title ?? this.title,
      uri: uri,
      source: source,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      headers: headers,
      artwork: artwork ?? this.artwork,
      duration: duration ?? this.duration,
      downloadUrl: downloadUrl,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'uri': uri,
        'source': source.name,
        'artist': artist,
        'album': album,
        'headers': headers,
        'artwork': artwork,
        'duration': duration?.inMilliseconds,
        'downloadUrl': downloadUrl,
        'extra': extra,
      };

  static Track fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      uri: json['uri'] as String,
      source: TrackSource.values.firstWhere(
        (TrackSource s) => s.name == json['source'],
        orElse: () => TrackSource.local,
      ),
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      headers: rawHeaders is Map
          ? rawHeaders.map(
              (Object? k, Object? v) => MapEntry<String, String>(
                k.toString(),
                v.toString(),
              ),
            )
          : null,
      artwork: json['artwork'] as String?,
      duration: json['duration'] is int
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      downloadUrl: json['downloadUrl'] as String?,
      extra: json['extra'] as String?,
    );
  }
}
