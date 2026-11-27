import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 轻量 JSON 文件存储。用于队列、收藏、音乐库索引这类结构化但不海量的数据。
///
/// 刻意不引入 SQLite：电台缓存与曲库索引在数万条量级下 JSON 足够，
/// 少一个原生依赖就少一类平台构建问题。
class JsonStore {
  JsonStore(this.fileName);

  final String fileName;
  Directory? _cachedDir;

  Future<Directory> _dir() async {
    final Directory? cached = _cachedDir;
    if (cached != null) return cached;
    final Directory dir = await getApplicationSupportDirectory();
    final Directory target = Directory(p.join(dir.path, 'listener'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    _cachedDir = target;
    return target;
  }

  Future<File> file() async => File(p.join((await _dir()).path, fileName));

  Future<Map<String, dynamic>> read() async {
    try {
      final File f = await file();
      if (!await f.exists()) return <String, dynamic>{};
      final String raw = await f.readAsString();
      if (raw.trim().isEmpty) return <String, dynamic>{};
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      // 配置文件损坏时不能阻断启动。
      return <String, dynamic>{};
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    final File f = await file();
    await f.writeAsString(jsonEncode(data), flush: true);
  }
}

/// 提供应用私有目录，供封面缓存、下载落盘使用。
class AppPaths {
  AppPaths._();

  static Future<Directory> supportDir() async {
    final Directory dir = await getApplicationSupportDirectory();
    final Directory target = Directory(p.join(dir.path, 'listener'));
    if (!await target.exists()) await target.create(recursive: true);
    return target;
  }

  static Future<Directory> coverCacheDir() async {
    final Directory target =
        Directory(p.join((await supportDir()).path, 'covers'));
    if (!await target.exists()) await target.create(recursive: true);
    return target;
  }

  static Future<Directory> downloadDir() async {
    if (Platform.isAndroid) {
      // Android 10+ 分区存储禁止直接写公共 Download 目录，
      // 这里落在应用专属外部目录，无需任何存储权限。
      final Directory? ext = await getExternalStorageDirectory();
      final Directory base = ext ?? await supportDir();
      final Directory target = Directory(p.join(base.path, 'downloads'));
      if (!await target.exists()) await target.create(recursive: true);
      return target;
    }
    final Directory? downloads = await getDownloadsDirectory();
    final Directory target =
        Directory(p.join(downloads?.path ?? (await supportDir()).path, 'Listener'));
    if (!await target.exists()) await target.create(recursive: true);
    return target;
  }
}
