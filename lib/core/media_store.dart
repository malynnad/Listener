import 'dart:io';

import 'package:flutter/services.dart';

/// 把下载好的音频放进系统媒体库。
///
/// Android 10+ 的分区存储不允许应用直接往 `/storage/emulated/0/Music` 写文件，
/// 必须经 MediaStore 申请记录再写入（Kotlin 侧实现），否则一律 Permission denied。
/// 桌面端不需要通道，直接落到 `~/Music/Listener`。
class MediaSaver {
  MediaSaver._();

  static const MethodChannel _channel = MethodChannel('listener/media');

  /// 保存成功返回文件绝对路径；失败返回 null，由调用方决定降级策略。
  static Future<String?> saveAudio({
    required String path,
    required String name,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>(
        'saveAudio',
        <String, String>{'path': path, 'name': name},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
