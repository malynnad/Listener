import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// mpv 内核的最小封装。
///
/// 选择 media_kit 而非 just_audio 的关键原因：`Media` 支持 `httpHeaders`，
/// B 站音轨必须带 `Referer: https://www.bilibili.com` 才不返回 403，
/// 而浏览器/系统播放器都无法为媒体请求单独注入请求头。
class PlaybackService {
  PlaybackService() : _player = _create();

  Player _player;

  /// 底层实例会被 [recreate] 替换，调用方每次都应重新读取该 getter。
  Player get player => _player;

  static Player _create() => Player(
        configuration: const PlayerConfiguration(
          title: 'Listener',
        ),
      );

  /// 硬停止：先清空播放列表再停播，确保直播流的上游连接被断开。
  ///
  /// 单纯 `pause()` 对 HTTP 直播流不可靠——mpv 仍会继续拉流，
  /// 部分设备上 AudioTrack 也不会被释放，表现就是"停不掉"或"换台后还有旧声音"。
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // 实例已 dispose 时忽略，交给上层重建。
    }
  }

  /// 重建底层 mpv 实例。
  ///
  /// 遇到 AudioTrack 迟迟不释放（换台后仍能听到上一个电台）时，
  /// 只有销毁 mpv 实例才能把音频输出彻底交还给系统。
  Future<void> recreate() async {
    final Player old = _player;
    _player = _create();
    try {
      await old.dispose();
    } catch (_) {
      // 旧实例可能已经处于异常状态，忽略销毁错误。
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
