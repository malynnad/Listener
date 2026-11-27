import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../controllers/player_controller.dart';
import '../../core/json_store.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';

/// B 站曲目的重新解析钩子。歌单里只存元数据，播放前用它换回可用的直链。
typedef BiliResolver = Future<Track?> Function(String bvid);

/// 歌单：本地曲目与 B 站曲目可以混在同一个歌单里，播放在这里统一处理。
class PlaylistController extends ChangeNotifier {
  PlaylistController({
    required PlayerController player,
    JsonStore? store,
    BiliResolver? resolveBili,
  })  : _player = player,
        _store = store ?? JsonStore('playlists.json'),
        _resolveBili = resolveBili {
    unawaited(load());
  }

  final PlayerController _player;
  final JsonStore _store;
  final BiliResolver? _resolveBili;

  /// 首次使用时自动建一个，免得点爱心还要先想名字。
  static const String defaultPlaylistName = '我喜欢的音乐';

  List<Playlist> _playlists = <Playlist>[];
  bool _preparing = false;
  String? _error;

  List<Playlist> get playlists => List<Playlist>.unmodifiable(_playlists);
  bool get preparing => _preparing;
  String? get error => _error;

  Playlist? byId(String id) {
    for (final Playlist p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 任一歌单里有这首就算收藏，界面据此决定爱心是实心还是空心。
  bool isFavorite(String trackId) =>
      _playlists.any((Playlist p) => p.contains(trackId));

  /// 这首已在哪些歌单里，用于选择弹窗的勾选状态。
  Set<String> playlistsOf(String trackId) => <String>{
        for (final Playlist p in _playlists)
          if (p.contains(trackId)) p.id,
      };

  Future<void> load() async {
    final Map<String, dynamic> data = await _store.read();
    final List<dynamic> raw =
        data['playlists'] as List<dynamic>? ?? <dynamic>[];
    _playlists = raw
        .whereType<Map<String, dynamic>>()
        .map(Playlist.fromJson)
        .where((Playlist p) => p.id.isNotEmpty)
        .toList();
    if (_playlists.isEmpty) {
      _playlists = <Playlist>[
        Playlist(
          id: _newId(),
          name: defaultPlaylistName,
        ),
      ];
      await _persist();
    }
    notifyListeners();
  }

  Future<Playlist> create(String name) async {
    final String trimmed = name.trim();
    final Playlist playlist = Playlist(
      id: _newId(),
      name: trimmed.isEmpty ? '未命名歌单' : trimmed,
    );
    _playlists = <Playlist>[..._playlists, playlist];
    await _persist();
    notifyListeners();
    return playlist;
  }

  Future<void> rename(String id, String name) async {
    final Playlist? p = byId(id);
    if (p == null) return;
    p.name = name.trim().isEmpty ? p.name : name.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _playlists = _playlists.where((Playlist p) => p.id != id).toList();
    await _persist();
    notifyListeners();
  }

  /// 加入歌单。同一首歌不会重复入单。
  Future<bool> addTrack(String playlistId, Track track) async {
    final Playlist? p = byId(playlistId);
    if (p == null) return false;
    if (p.contains(track.id)) return false;
    p.tracks.add(track);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    final Playlist? p = byId(playlistId);
    if (p == null) return;
    p.tracks.removeWhere((Track t) => t.id == trackId);
    await _persist();
    notifyListeners();
  }

  /// 播放整个歌单。
  ///
  /// 本地曲目先过滤掉已删除的文件，B 站曲目按 bvid 重新取流；
  /// 解析失败的单曲直接跳过，不让一首失效的歌毁掉整个歌单。
  Future<void> playPlaylist(String playlistId, {int at = 0}) async {
    final Playlist? p = byId(playlistId);
    if (p == null || p.tracks.isEmpty) return;
    _preparing = true;
    _error = null;
    notifyListeners();
    try {
      final List<Track?> resolved =
          List<Track?>.filled(p.tracks.length, null);
      const int concurrency = 3;
      for (int start = 0; start < p.tracks.length; start += concurrency) {
        final int end = math.min(start + concurrency, p.tracks.length);
        await Future.wait(<Future<void>>[
          for (int i = start; i < end; i++) _prepare(p.tracks[i], i, resolved),
        ]);
      }
      final List<Track> ready = resolved.whereType<Track>().toList();
      if (ready.isEmpty) {
        _error = '歌单里的曲目都已失效';
        return;
      }
      final Track target = p.tracks[at.clamp(0, p.tracks.length - 1)];
      final int found = ready.indexWhere((Track t) => t.id == target.id);
      await _player.playAll(ready, at: found < 0 ? 0 : found);
    } finally {
      _preparing = false;
      notifyListeners();
    }
  }

  Future<void> _prepare(Track track, int slot, List<Track?> out) async {
    if (track.source == TrackSource.local) {
      if (File(track.uri).existsSync()) out[slot] = track;
      return;
    }
    if (track.source != TrackSource.bilibili) return;
    final String bvid =
        track.id.startsWith('bili:') ? track.id.substring(5) : '';
    if (bvid.isEmpty) return;
    try {
      final Track? fresh = await _resolveBili?.call(bvid);
      if (fresh != null) out[slot] = fresh;
    } catch (_) {
      // 单曲失败：保持空缺，最后统一过滤。
    }
  }

  Future<void> _persist() => _store.write(<String, dynamic>{
        'playlists': _playlists.map((Playlist p) => p.toJson()).toList(),
      });

  String _newId() =>
      'pl_${DateTime.now().microsecondsSinceEpoch}';
}
