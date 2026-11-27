import 'track.dart';
import 'package:listener/core/config.dart';

/// radio-browser.info 的电台条目。
class RadioStation {
  const RadioStation({
    required this.uuid,
    required this.name,
    required this.url,
    this.favicon,
    this.country,
    this.countryCode,
    this.tags,
    this.codec,
    this.bitrate,
    this.votes,
  });

  final String uuid;
  final String name;

  /// 已解析的播放直链（`url_resolved`）。
  final String url;
  final String? favicon;
  final String? country;
  final String? countryCode;
  final String? tags;
  final String? codec;
  final int? bitrate;
  final int? votes;

  String get subtitle {
    final List<String> parts = <String>[
      if (country != null && country!.isNotEmpty) country!,
      if (bitrate != null && bitrate! > 0) '${bitrate}kbps',
      if (codec != null && codec!.isNotEmpty) codec!.toUpperCase(),
    ];
    return parts.join(' · ');
  }

  Track toTrack() {
    return Track(
      id: 'radio:$uuid',
      title: name,
      uri: url,
      source: TrackSource.radio,
      artist: subtitle.isEmpty ? '网络电台' : subtitle,
      artwork: _normalizeIcon(favicon),
      headers: const <String, String>{
        'User-Agent': AppConfig.userAgent,
      },
      extra: tags,
    );
  }

  static String? _normalizeIcon(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://')) return 'https://${raw.substring(7)}';
    return raw;
  }

  static RadioStation fromJson(Map<String, dynamic> json) {
    return RadioStation(
      uuid: (json['stationuuid'] ?? '').toString(),
      name: (json['name'] ?? '未命名电台').toString().trim(),
      url: (json['url_resolved'] ?? json['url'] ?? '').toString(),
      favicon: json['favicon']?.toString(),
      country: json['country']?.toString(),
      countryCode: json['countrycode']?.toString(),
      tags: json['tags']?.toString(),
      codec: json['codec']?.toString(),
      bitrate: int.tryParse('${json['bitrate'] ?? ''}'),
      votes: int.tryParse('${json['votes'] ?? ''}'),
    );
  }
}
