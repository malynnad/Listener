import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../core/config.dart';
import '../../core/json_store.dart';
import '../../models/track.dart';

/// 本地音乐库。
///
/// 扫描放在独立 isolate 里跑：机械硬盘上 5000 首曲目的标签读取约 3~6 秒，
/// 放主 isolate 会直接卡死界面。索引结果按路径缓存，重启不重复解析。
class LibraryController extends ChangeNotifier {
  LibraryController({JsonStore? store})
      : _store = store ?? JsonStore('library.json') {
    unawaited(load());
  }

  final JsonStore _store;

  List<String> _folders = <String>[];
  List<String> _files = <String>[];
  List<Track> _tracks = <Track>[];
  bool _scanning = false;
  String _query = '';
  String? _status;

  List<String> get folders => List<String>.unmodifiable(_folders);
  List<Track> get tracks => List<Track>.unmodifiable(_tracks);
  bool get scanning => _scanning;
  String get query => _query;
  String? get status => _status;
  bool get isEmpty => _tracks.isEmpty;

  List<Track> get visible {
    if (_query.trim().isEmpty) return tracks;
    final String q = _query.trim().toLowerCase();
    return _tracks
        .where((Track t) =>
            t.title.toLowerCase().contains(q) ||
            (t.artist ?? '').toLowerCase().contains(q) ||
            (t.album ?? '').toLowerCase().contains(q))
        .toList();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  Future<void> load() async {
    final Map<String, dynamic> data = await _store.read();
    _folders = (data['folders'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => e.toString())
        .toList();
    _files = (data['files'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => e.toString())
        .toList();
    final List<dynamic> cached = data['tracks'] as List<dynamic>? ?? <dynamic>[];
    _tracks = cached
        .whereType<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
    // 缓存里可能包含已被删除的文件，启动后静默清一次。
    _tracks = _tracks.where((Track t) => File(t.uri).existsSync()).toList();
    notifyListeners();
    if (_tracks.isEmpty && (_folders.isNotEmpty || _files.isNotEmpty)) {
      unawaited(rescan());
    }
  }

  Future<void> addFolder() async {
    // Android 的分区存储把目录暴露成 content:// URI，dart:io 无法遍历，
    // 因此移动端走“授权 + 扫描约定目录”，桌面端才提供任意目录选择。
    if (Platform.isAndroid) {
      await scanDeviceMusic();
      return;
    }
    final Uri? uri = await FilePicker.pickDirectory(
      dialogTitle: '选择音乐文件夹',
    );
    if (uri == null) return;
    final String path =
        uri.scheme == 'file' ? uri.toFilePath() : uri.path;
    if (path.isEmpty) return;
    if (_folders.contains(path)) {
      _status = '该文件夹已在库中';
      notifyListeners();
      return;
    }
    _folders = <String>[..._folders, path];
    await _persist();
    await rescan();
  }

  /// Android：申请媒体权限后扫描约定的音乐目录。
  ///
  /// 分区存储下无法遍历整块外部存储，只能读系统媒体目录与各家播放器的下载目录。
  /// 权限在 Android 13+ 是 READ_MEDIA_AUDIO，12 及以下是 READ_EXTERNAL_STORAGE；
  /// 旧系统上请求 audio 会直接返回 denied，因此逐个尝试、任一通过即可。
  ///
  /// 应用自己的外部目录（B 站音轨的落地处）不受分区存储限制、也不需要任何权限，
  /// 所以无论媒体权限是否授予都会一并扫描——否则用户下载完在本地库里根本看不到。
  Future<void> scanDeviceMusic() async {
    if (!Platform.isAndroid) return;
    _status = '正在申请媒体权限…';
    notifyListeners();

    final String ownDownloads = (await AppPaths.downloadDir()).path;

    PermissionStatus granted = await Permission.audio.request();
    if (!granted.isGranted) {
      granted = await Permission.storage.request();
    }
    final bool hasMediaAccess = granted.isGranted;

    final List<String> roots = <String>[
      if (hasMediaAccess) ...AppConfig.androidMusicRoots,
      ownDownloads,
    ].where((String dir) => Directory(dir).existsSync()).toList();
    if (roots.isEmpty) {
      _status = '没有找到可扫描的目录，可改用「添加文件」手动选择';
      notifyListeners();
      return;
    }
    _folders = <String>{..._folders, ...roots}.toList();
    await _persist();
    await rescan();
    if (!hasMediaAccess) {
      _status = granted.isPermanentlyDenied
          ? '媒体权限已被拒绝，本次只扫描了应用内下载目录；可到 设置 → 应用 → Listener → 权限 开启'
          : '未授予媒体权限，本次只扫描了应用内下载目录';
      notifyListeners();
    }
  }

  Future<void> addFiles() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      dialogTitle: '选择音频文件',
      type: FileType.custom,
      allowedExtensions: AppConfig.audioExtensions
          .map((String e) => e.replaceFirst('.', ''))
          .toList(),
    );
    final List<String> paths = picked
        .map((PlatformFile f) => f.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return;
    _files = <String>{..._files, ...paths}.toList();
    await _persist();
    await rescan();
  }

  Future<void> removeFolder(String path) async {
    _folders = _folders.where((String f) => f != path).toList();
    _tracks = _tracks
        .where((Track t) => !p.isWithin(path, t.uri))
        .toList();
    notifyListeners();
    await _persist();
  }

  Future<void> rescan() async {
    if (_scanning) return;
    if (_folders.isEmpty && _files.isEmpty) {
      _status = '还没有添加音乐';
      notifyListeners();
      return;
    }
    _scanning = true;
    _status = null;
    notifyListeners();
    try {
      final Directory coverDir = await AppPaths.coverCacheDir();
      // 必须先把参数取成本地不可变副本再进闭包：
      // 闭包里直接访问 _folders 会捕获 this，把整个 Provider 对象图（含 Timer、
      // 其它控制器）带进 isolate，触发 “object is unsendable” 而扫描直接失败。
      final List<String> folders = List<String>.of(_folders);
      final List<String> files = List<String>.of(_files);
      final String coverPath = coverDir.path;
      final List<Map<String, dynamic>> raw = await Isolate.run(
        () => scanInIsolate(folders, files, coverPath),
      );
      _tracks = raw.map(Track.fromJson).toList()
        ..sort((Track a, Track b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      _status = _tracks.isEmpty ? '找到 0 首，检查文件夹里是否有音频文件' : null;
      await _persist();
    } catch (e) {
      // 异常信息可能带整段调用栈，界面上只留第一行。
      final String brief = e.toString().split('\n').first;
      _status = '扫描失败：$brief';
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await _store.write(<String, dynamic>{
      'folders': _folders,
      'files': _files,
      'tracks': _tracks.map((Track t) => t.toJson()).toList(),
    });
  }
}

/// 在 isolate 中执行：遍历目录、读标签、抽取封面。
///
/// 必须是顶层/静态函数，且只接收可跨 isolate 传递的参数。
List<Map<String, dynamic>> scanInIsolate(
  List<String> folders,
  List<String> files,
  String coverDir,
) {
  final Set<String> seen = <String>{};
  final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];

  void handle(String path) {
    if (!seen.add(path)) return;
    final String ext = p.extension(path).toLowerCase();
    if (!AppConfig.audioExtensions.contains(ext)) return;
    final File file = File(path);
    String title = p.basenameWithoutExtension(path);
    String? artist;
    String? album;
    Duration? duration;
    String? artwork;
    String? extra;
    try {
      final AudioMetadata meta = readMetadata(file, getImage: true);
      if ((meta.title ?? '').trim().isNotEmpty) title = meta.title!.trim();
      artist = (meta.artist ?? '').trim().isEmpty ? null : meta.artist!.trim();
      album = (meta.album ?? '').trim().isEmpty ? null : meta.album!.trim();
      duration = meta.duration;
      if (meta.bitrate != null && meta.bitrate! > 0) {
        extra = '${(meta.bitrate! / 1000).round()}kbps';
      }
      if (meta.pictures.isNotEmpty) {
        final Picture pic = meta.pictures.first;
        final String hash = md5.convert(pic.bytes).toString();
        final String coverPath = p.join(coverDir, '$hash.img');
        final File cover = File(coverPath);
        if (!cover.existsSync()) {
          cover.writeAsBytesSync(pic.bytes, flush: true);
        }
        artwork = coverPath;
      }
    } catch (_) {
      // 损坏文件或不受支持的容器：退回文件名，不影响整库扫描。
    }
    result.add(<String, dynamic>{
      'id': path,
      'title': title,
      'uri': path,
      'source': TrackSource.local.name,
      'artist': artist,
      'album': album,
      'artwork': artwork,
      'duration': duration?.inMilliseconds,
      'extra': extra,
    });
  }

  for (final String folder in folders) {
    try {
      final Directory dir = Directory(folder);
      if (!dir.existsSync()) continue;
      for (final FileSystemEntity entity
          in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        // 手机上 Android/data 等目录体量大且不含用户音乐，直接跳过；
        // 但本应用自己的下载目录要放行，否则 B 站下载的曲子扫不到。
        final String path = entity.path;
        if (!path.contains(AppConfig.ownDataSegment) &&
            AppConfig.scanSkipSegments.any(path.contains)) {
          continue;
        }
        handle(path);
      }
    } catch (_) {
      // 无权限的目录直接跳过。
    }
  }
  for (final String file in files) {
    handle(file);
  }
  return result;
}
