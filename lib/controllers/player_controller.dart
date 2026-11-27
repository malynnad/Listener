import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../core/json_store.dart';
import '../models/track.dart';
import '../services/playback_service.dart';

enum LoopMode { off, all, one }

/// 队列 + 播放状态。UI 只依赖这一个 ChangeNotifier。
///
/// 位置更新用 500ms 轮询而非直接转发 mpv 的高频事件，
/// 否则进度条每帧触发重建，移动端会明显掉帧。
class PlayerController extends ChangeNotifier {
  PlayerController({
    PlaybackService? playback,
    JsonStore? store,
  })  : _playback = playback ?? PlaybackService(),
        _store = store ?? JsonStore('queue.json') {
    _bind();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    unawaited(_restore());
  }

  /// 打开媒体是异步的，用户连点两个电台时会有多个 open 并发。
  /// 用自增序号作废旧请求，避免旧流的 onLoad 覆盖新流的状态。
  int _openSeq = 0;
  bool _disposed = false;

  /// 播放器里是否已经装着一个可播的音源。
  /// stop() 会清空 mpv 的播放列表，此时再 play() 是无声的，
  /// 必须先重新 open 当前曲目。
  bool _loaded = false;

  /// 当前已装载音源的类型。用于判断是否从直播流切走。
  TrackSource? _loadedSource;

  final PlaybackService _playback;
  final JsonStore _store;
  final Random _random = Random();

  Player get _player => _playback.player;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];
  Timer? _ticker;

  List<Track> _queue = <Track>[];
  int _index = -1;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  LoopMode _repeat = LoopMode.all;
  bool _shuffle = false;
  double _volume = 0.85;
  bool _advancing = false;

  List<Track> get queue => List<Track>.unmodifiable(_queue);
  int get index => _index;
  Track? get current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  bool get playing => _playing;
  bool get buffering => _buffering;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get error => _error;
  LoopMode get repeat => _repeat;
  bool get shuffle => _shuffle;
  double get volume => _volume;
  bool get hasPrevious => _index > 0 || _repeat == LoopMode.all;
  bool get hasNext => _queue.isNotEmpty;

  /// 直播流：没有确定的时长，进度条无意义。
  bool get isLive => current?.source == TrackSource.radio;

  void _bind() {
    for (final StreamSubscription<dynamic> sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _subs.add(_player.stream.playing.listen((bool value) {
      _playing = value;
      _log('playing=$value');
      notifyListeners();
    }));
    _subs.add(_player.stream.buffering.listen((bool value) {
      _buffering = value;
      notifyListeners();
    }));
    _subs.add(_player.stream.completed.listen((bool value) {
      _log('completed=$value source=${current?.source}');
      if (value) unawaited(_onCompleted());
    }));
    _subs.add(_player.stream.error.listen((String value) {
      // 电台流最常在这里炸：链接过期或服务端主动断开。
      _log('error=$value');
      _error = _humanizeError(value);
      notifyListeners();
    }));
    _subs.add(_player.stream.volume.listen((double value) {
      _volume = (value / 100).clamp(0.0, 1.0);
      notifyListeners();
    }));
  }

  static const bool _verbose = true;

  void _log(String message) {
    if (_verbose) debugPrint('[PlayerController] $message');
  }

  void _tick() {
    final Duration pos = _player.state.position;
    final Duration dur = _player.state.duration;
    bool changed = false;
    if ((pos - _position).inMilliseconds.abs() > 200) {
      _position = pos;
      changed = true;
    }
    if (dur != _duration) {
      _duration = dur;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> _onCompleted() async {
    if (_advancing) return;
    _advancing = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      // 直播流没有"播完"这回事，走到 completed 只说明上游断开了。
      // 此时自动切下一个台，叠加尚未散去的旧音频，听感就是"两个台在同时播"，
      // 而且用户按暂停后马上又会被下一个台顶掉，像关不掉。电台一律停在原地。
      if (current?.source == TrackSource.radio) {
        await stop();
        _error = '电台连接已断开，重新点击该台即可继续';
        notifyListeners();
        return;
      }
      next(auto: true);
    } finally {
      _advancing = false;
    }
  }

  String _humanizeError(String raw) {
    final String lower = raw.toLowerCase();
    if (lower.contains('403')) return '音源返回 403：链接可能已过期，重新搜索一次即可';
    if (lower.contains('404')) return '音源不存在（404）';
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return '连接超时，请检查网络或换一个电台';
    }
    if (lower.contains('failed to open')) return '无法打开该音源';
    return '播放失败：$raw';
  }

  Future<void> playAll(List<Track> tracks, {int at = 0}) async {
    if (tracks.isEmpty) return;
    _queue = List<Track>.of(tracks);
    _index = at.clamp(0, tracks.length - 1);
    // 电台是一组独立直播流，不应循环连播：某台断流后自动跳下一个台，
    // 用户会以为"关不掉"。切到电台队列时强制关闭循环，走完就停。
    if (_queue.every((Track t) => t.source == TrackSource.radio) &&
        _repeat != LoopMode.off) {
      _repeat = LoopMode.off;
    }
    await _openCurrent();
  }

  Future<void> playSingle(Track track) =>
      playAll(<Track>[track], at: 0);

  /// 跳到队列中指定位置（队列面板点击时使用）。
  Future<void> playAt(int target) async {
    if (target < 0 || target >= _queue.length) return;
    _index = target;
    await _openCurrent();
  }

  /// 追加到队列末尾，不打断当前播放。
  void enqueue(Track track) {
    _queue = <Track>[..._queue, track];
    if (_index < 0) {
      _index = 0;
      unawaited(_openCurrent());
    }
    notifyListeners();
    unawaited(_persist());
  }

  /// 插入到当前曲目之后。
  void playNext(Track track) {
    final int insertAt = _index < 0 ? 0 : _index + 1;
    final List<Track> next = List<Track>.of(_queue)..insert(insertAt, track);
    _queue = next;
    if (_index < 0) _index = 0;
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _openCurrent() async {
    final Track? track = current;
    if (track == null) return;
    final int seq = ++_openSeq;
    _error = null;
    _position = Duration.zero;
    _duration = track.duration ?? Duration.zero;
    notifyListeners();
    try {
      // 关键顺序：先硬停上一个流，再打开新流。
      // 直接 open 会让 mpv 在上游连接尚未断开时加载新地址，
      // 直播流尤其明显——旧台的缓冲还在播，新台又响起来，听起来就是两路重叠。
      await _playback.stop();
      if (seq != _openSeq || _disposed) return;
      await _releaseLiveOutput();
      if (seq != _openSeq || _disposed) return;
      _log('open #$seq -> ${track.source} ${track.title}');
      await _player.open(
        Media(track.uri, httpHeaders: track.headers),
        play: true,
      );
      if (seq != _openSeq || _disposed) return;
      _loaded = true;
      _loadedSource = track.source;
      unawaited(_persist());
    } catch (e) {
      if (seq != _openSeq || _disposed) return;
      _log('open #$seq failed: $e');
      _error = _humanizeError(e.toString());
      notifyListeners();
    }
  }

  /// 从直播流切走时，销毁并重建底层 mpv 实例。
  ///
  /// 只发 stop 不够：部分设备上 libmpv 的 AudioTrack 在 stop 之后不会立刻归还系统，
  /// 换台后仍能听到上一个电台的声音，叠加起来就像两路广播同时播。
  /// 重建实例是唯一可靠的收口方式，代价约 200ms，且只发生在"从电台切到别的内容"时。
  Future<void> _releaseLiveOutput() async {
    if (_loadedSource != TrackSource.radio) return;
    _log('release live audio output');
    _loaded = false;
    _loadedSource = null;
    _playing = false;
    _buffering = false;
    await _playback.recreate();
    if (_disposed) return;
    _bind();
    await _player.setVolume(_volume * 100);
  }

  /// 真正停下来：断开上游连接、清空播放列表，并把 UI 状态复位。
  ///
  /// 只调用 `pause()` 对直播流不够——mpv 会继续拉流，部分设备上音频输出
  /// 也不会释放，用户看到的是"按了暂停但声音还在"。
  Future<void> stop() async {
    _openSeq++;
    await _playback.stop();
    _loaded = false;
    _loadedSource = null;
    _playing = false;
    _buffering = false;
    _position = Duration.zero;
    _log('stopped');
    notifyListeners();
  }

  void next({bool auto = false}) {
    if (_queue.isEmpty) return;
    if (_repeat == LoopMode.one && auto) {
      if (!_loaded) {
        unawaited(_openCurrent());
        return;
      }
      unawaited(_player.seek(Duration.zero));
      unawaited(_player.play());
      return;
    }
    if (_shuffle && _queue.length > 1) {
      int candidate = _index;
      while (candidate == _index) {
        candidate = _random.nextInt(_queue.length);
      }
      _index = candidate;
    } else if (_index + 1 < _queue.length) {
      _index++;
    } else if (_repeat == LoopMode.all) {
      _index = 0;
    } else {
      unawaited(stop());
      return;
    }
    unawaited(_openCurrent());
  }

  void previous() {
    if (_queue.isEmpty) return;
    // 播放超过 3 秒时，"上一首"先回到开头，符合常见播放器行为。
    if (_position.inSeconds >= 3 && _loaded) {
      unawaited(_player.seek(Duration.zero));
      return;
    }
    if (_index > 0) {
      _index--;
    } else if (_repeat == LoopMode.all) {
      _index = _queue.length - 1;
    } else {
      if (!_loaded) {
        unawaited(_openCurrent());
      } else {
        unawaited(_player.seek(Duration.zero));
      }
      return;
    }
    unawaited(_openCurrent());
  }

  void toggle() {
    if (current == null) return;
    // 停止后播放列表已被清空，直接 play() 不会有声音，需要重新装载。
    if (!_loaded) {
      unawaited(_openCurrent());
      return;
    }
    // 用自己维护的状态发 play/pause，而不是 playOrPause()：
    // 直播流切台时 mpv 的 playing 事件会滞后，playOrPause 容易算反，
    // 出现"按暂停反而继续播"的现象。
    if (_playing) {
      _log('pause');
      unawaited(_player.pause());
    } else {
      _log('play');
      unawaited(_player.play());
    }
  }

  void seek(Duration target) {
    if (!_loaded) return;
    _position = target;
    notifyListeners();
    unawaited(_player.seek(target));
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    notifyListeners();
    unawaited(_player.setVolume(_volume * 100));
  }

  void cycleRepeat() {
    _repeat = LoopMode.values[(_repeat.index + 1) % LoopMode.values.length];
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  Future<void> clearQueue() async {
    _openSeq++;
    await _playback.stop();
    _queue = <Track>[];
    _index = -1;
    _loaded = false;
    _loadedSource = null;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await _store.write(<String, dynamic>{
      'index': _index,
      'tracks': _queue.map((Track t) => t.toJson()).toList(),
    });
  }

  Future<void> _restore() async {
    final Map<String, dynamic> data = await _store.read();
    final Object? rawTracks = data['tracks'];
    if (rawTracks is! List || rawTracks.isEmpty) return;
    try {
      _queue = rawTracks
          .whereType<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList();
      final Object? rawIndex = data['index'];
      _index = rawIndex is int && rawIndex >= 0 && rawIndex < _queue.length
          ? rawIndex
          : (_queue.isEmpty ? -1 : 0);
      dropCurrent();
      notifyListeners();
    } catch (_) {
      _queue = <Track>[];
      _index = -1;
    }
  }

  /// 恢复队列但不自动播放：把当前曲目定位到队列头部，避免用户一打开应用就出声。
  void dropCurrent() {
    final Track? track = current;
    if (track == null) return;
    _duration = track.duration ?? Duration.zero;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    for (final StreamSubscription<dynamic> sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_playback.dispose());
    super.dispose();
  }
}
