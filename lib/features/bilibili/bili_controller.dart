import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../controllers/player_controller.dart';
import '../../core/config.dart';
import '../../models/track.dart';
import 'bili_auth.dart';
import 'bili_client.dart';
import 'bili_downloader.dart';
import 'bili_models.dart';

/// 串起 B 站的登录、搜索、取流、下载与播放。
class BiliController extends ChangeNotifier {
  BiliController({
    required PlayerController player,
    BiliAuthService? auth,
    BiliClient? client,
    BiliDownloader? downloader,
  })  : _player = player,
        auth = auth ?? BiliAuthService(),
        _downloader = downloader ?? BiliDownloader(),
        _clientOverride = client {
    unawaited(init());
  }

  final PlayerController _player;
  final BiliAuthService auth;
  final BiliDownloader _downloader;
  final BiliClient? _clientOverride;
  late final BiliClient _client =
      _clientOverride ?? BiliClient(cookieProvider: () => auth.cookies);

  final StreamController<String> _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  BiliUser? _user;
  List<BiliSearchResult> _results = <BiliSearchResult>[];
  bool _searching = false;
  String? _error;
  String _keyword = '';

  final Map<String, double> _progress = <String, double>{};
  final Map<String, File> _downloads = <String, File>{};
  final Map<String, Track> _trackCache = <String, Track>{};
  final Map<String, DateTime> _cacheAt = <String, DateTime>{};

  BiliUser? get user => _user;
  List<BiliSearchResult> get results => List<BiliSearchResult>.unmodifiable(_results);
  bool get searching => _searching;
  String? get error => _error;
  String get keyword => _keyword;
  bool get isLoggedIn => auth.isLoggedIn;
  Map<String, double> get progress => Map<String, double>.unmodifiable(_progress);
  Map<String, File> get downloads => Map<String, File>.unmodifiable(_downloads);

  Future<void> init() async {
    await auth.restore();
    if (auth.isLoggedIn) await refreshUser();
    notifyListeners();
  }

  Future<void> refreshUser() async {
    if (!auth.isLoggedIn) {
      _user = null;
      notifyListeners();
      return;
    }
    try {
      _user = await _client.fetchUser();
    } on BiliException catch (e) {
      _error = e.friendly;
    } catch (_) {
      // 网络异常时保留登录态，仅用户信息为空。
    }
    notifyListeners();
  }

  Future<void> search(String keyword, {int page = 1}) async {
    final String kw = keyword.trim();
    if (kw.isEmpty) return;
    _keyword = kw;
    _searching = true;
    _error = null;
    notifyListeners();
    try {
      _results = await _client.search(kw, page: page);
      if (_results.isEmpty) _error = '没有搜到结果，换个关键词试试';
    } on BiliException catch (e) {
      _error = e.friendly;
      _results = <BiliSearchResult>[];
    } catch (e) {
      _error = '搜索失败：$e';
      _results = <BiliSearchResult>[];
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  /// 解析音轨并做 20 分钟缓存：直链有效期约 2 小时，缓存过久会拿到 403。
  Future<Track> resolve(BiliSearchResult item) async {
    final Track? cached = _trackCache[item.bvid];
    final DateTime? at = _cacheAt[item.bvid];
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 20)) {
      return cached;
    }
    final BiliVideoInfo info = await _client.resolveAudio(item.bvid);
    final BiliAudioStream best = info.best!;
    final Track track = Track(
      id: 'bili:${item.bvid}',
      title: info.title.isEmpty ? item.title : info.title,
      artist: info.owner.isEmpty ? item.author : info.owner,
      uri: best.url,
      headers: AppConfig.biliMediaHeaders,
      artwork: info.cover ?? item.cover,
      duration: info.duration.inSeconds > 0 ? info.duration : item.duration,
      source: TrackSource.bilibili,
      downloadUrl: best.url,
      extra: best.label,
    );
    _trackCache[item.bvid] = track;
    _cacheAt[item.bvid] = DateTime.now();
    return track;
  }

  Future<void> play(BiliSearchResult item) async {
    try {
      _messages.add('正在解析音轨…');
      final Track track = await resolve(item);
      await _player.playAll(<Track>[track]);
    } on BiliException catch (e) {
      _messages.add(e.friendly);
    } catch (e) {
      _messages.add('播放失败：$e');
    }
  }

  Future<void> enqueue(BiliSearchResult item) async {
    try {
      final Track track = await resolve(item);
      _player.enqueue(track);
      _messages.add('已加入队列：${track.title}');
    } on BiliException catch (e) {
      _messages.add(e.friendly);
    } catch (e) {
      _messages.add('加入队列失败：$e');
    }
  }

  Future<void> download(BiliSearchResult item) async {
    if (_progress.containsKey(item.bvid)) return;
    _progress[item.bvid] = 0;
    notifyListeners();
    try {
      final Track track = await resolve(item);
      final File file = await _downloader.download(
        url: track.downloadUrl ?? track.uri,
        baseName: '${track.title} - ${track.artist ?? '未知'}',
        onProgress: (double p) {
          _progress[item.bvid] = p;
          notifyListeners();
        },
      );
      _downloads[item.bvid] = file;
      _messages.add('已保存：${file.path}');
    } on BiliDownloadException catch (e) {
      _messages.add(e.message);
    } on BiliException catch (e) {
      _messages.add(e.friendly);
    } catch (e) {
      _messages.add('下载失败：$e');
    } finally {
      _progress.remove(item.bvid);
      notifyListeners();
    }
  }

  Future<void> openDownloadFolder() async {
    final Directory dir = await _downloader.targetDir();
    if (Platform.isMacOS) {
      await Process.run('open', <String>[dir.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', <String>[dir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', <String>[dir.path]);
    } else {
      _messages.add('下载目录：${dir.path}');
    }
  }

  Future<void> logout() async {
    await auth.logout();
    _user = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_messages.close());
    super.dispose();
  }
}
