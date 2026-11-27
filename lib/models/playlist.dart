import 'track.dart';

/// 用户歌单。可以同时放本地曲目和 B 站曲目——这是两者“互通”的落点。
///
/// B 站曲目入单时只存元数据，[Track.uri] 留空：直链有效期约两小时，
/// 存下来第二天必然失效，播放时再按 `bili:<bvid>` 重新解析。
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<Track>? tracks,
    DateTime? createdAt,
  })  : tracks = tracks ?? <Track>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final List<Track> tracks;
  final DateTime createdAt;

  bool contains(String trackId) =>
      tracks.any((Track t) => t.id == trackId);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'tracks': tracks.map((Track t) => t.toJson()).toList(),
      };

  static Playlist fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw =
        json['tracks'] as List<dynamic>? ?? <dynamic>[];
    return Playlist(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '未命名歌单').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      tracks: raw
          .whereType<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList(),
    );
  }
}
