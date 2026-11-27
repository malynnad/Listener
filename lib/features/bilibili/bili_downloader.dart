import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/json_store.dart';

/// B 站音轨下载器。
///
/// DASH 音频是分片 MP4（`.m4s`）。桌面端若本机有 ffmpeg 就无损转封装成 `.m4a`，
/// 没有则直接改名保存：分片 MP4 的音频在 mpv / ExoPlayer / VLC 中一般可直接播放，
/// 但部分系统播放器可能不识别。Android 端不内置 ffmpeg（体积成本过高），统一走后者。
class BiliDownloader {
  BiliDownloader({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: Duration.zero,
                headers: const <String, String>{
                  ...AppConfig.biliMediaHeaders,
                  'Accept': '*/*',
                  'Accept-Language': 'zh-CN,zh;q=0.9',
                },
              ),
            );

  final Dio _dio;

  Future<Directory> targetDir() => AppPaths.downloadDir();

  /// [onProgress] 参数为 0~1，总长度未知时传 -1。
  Future<File> download({
    required String url,
    required String baseName,
    void Function(double progress)? onProgress,
  }) async {
    final Directory dir = await targetDir();
    final String safeBase = sanitizeFileName(baseName);
    final File outFile = _dedupe(dir, safeBase);
    final File tempFile = File('${outFile.path}.part');

    await _dio.download(
      url,
      tempFile.path,
      options: Options(
        responseType: ResponseType.stream,
        headers: const <String, String>{
          ...AppConfig.biliMediaHeaders,
          'Accept': '*/*',
        },
      ),
      onReceiveProgress: (int received, int total) {
        if (onProgress == null) return;
        onProgress(total > 0 ? received / total : -1);
      },
    );

    if (!await tempFile.exists() || await tempFile.length() == 0) {
      throw const BiliDownloadException('下载内容为空，音源链接可能已过期');
    }

    final bool remuxed = await _tryRemux(tempFile, outFile);
    if (remuxed) {
      await tempFile.delete();
      onProgress?.call(1);
      return outFile;
    }
    await tempFile.rename(outFile.path);
    onProgress?.call(1);
    return outFile;
  }

  File _dedupe(Directory dir, String baseName) {
    File candidate = File(p.join(dir.path, '$baseName.m4a'));
    int index = 1;
    while (candidate.existsSync()) {
      candidate = File(p.join(dir.path, '$baseName ($index).m4a'));
      index++;
    }
    return candidate;
  }

  /// 桌面端调用系统 ffmpeg 做 `-c copy` 转封装；失败返回 false 由调用方降级。
  Future<bool> _tryRemux(File input, File output) async {
    if (Platform.isAndroid || Platform.isIOS) return false;
    try {
      final ProcessResult result = await Process.run(
        'ffmpeg',
        <String>[
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-i',
          input.path,
          '-vn',
          '-c:a',
          'copy',
          output.path,
        ],
      );
      if (result.exitCode != 0) return false;
      return await output.exists() && await output.length() > 0;
    } catch (_) {
      // 没装 ffmpeg：走改名兜底。
      return false;
    }
  }
}

class BiliDownloadException implements Exception {
  const BiliDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
