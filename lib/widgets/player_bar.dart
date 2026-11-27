import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/track.dart';
import 'cover_art.dart';

/// 底部播放栏。窄屏（手机）与宽屏（桌面）两套排布。
class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final PlayerController player = context.watch<PlayerController>();
    final Track? track = player.current;
    if (track == null) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 760;
          return compact ? _buildCompact(player, track) : _buildWide(player, track);
        },
      ),
    );
  }

  Widget _buildWide(PlayerController player, Track track) {
    final double maxMs = player.duration.inMilliseconds.toDouble();
    final double value = (_dragMs ?? player.position.inMilliseconds.toDouble())
        .clamp(0, maxMs <= 0 ? 1 : maxMs);

    return Row(
      children: <Widget>[
        CoverArt(source: track.artwork, size: 52, fallbackSeed: track.title),
        const SizedBox(width: 12),
        SizedBox(
          width: 190,
          child: _TitleBlock(track: track, error: player.error),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '上一首',
          onPressed: player.previous,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        _PlayButton(player: player),
        IconButton(
          tooltip: '下一首',
          onPressed: player.next,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: '停止播放',
          onPressed: player.stop,
          icon: const Icon(Icons.stop_rounded),
        ),
        const SizedBox(width: 12),
        if (player.isLive)
          const Expanded(child: _LiveBadge())
        else ...<Widget>[
          Text(
            formatDuration(_dragMs == null
                ? player.position
                : Duration(milliseconds: _dragMs!.round())),
            style: _timeStyle,
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: maxMs <= 0 ? 1 : maxMs,
              value: value,
              onChangeStart: (double v) => setState(() => _dragMs = v),
              onChanged: maxMs <= 0
                  ? null
                  : (double v) => setState(() => _dragMs = v),
              onChangeEnd: (double v) {
                player.seek(Duration(milliseconds: v.round()));
                setState(() => _dragMs = null);
              },
            ),
          ),
          Text(formatDuration(player.duration), style: _timeStyle),
        ],
        const SizedBox(width: 12),
        _ModeButtons(player: player),
        const SizedBox(width: 4),
        Icon(
          player.volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        SizedBox(
          width: 84,
          child: Slider(
            min: 0,
            max: 1,
            value: player.volume,
            onChanged: player.setVolume,
          ),
        ),
        IconButton(
          tooltip: '播放队列',
          onPressed: () => _showQueue(context, player),
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
  }

  Widget _buildCompact(PlayerController player, Track track) {
    final double maxMs = player.duration.inMilliseconds.toDouble();
    final double value = (_dragMs ?? player.position.inMilliseconds.toDouble())
        .clamp(0, maxMs <= 0 ? 1 : maxMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            CoverArt(source: track.artwork, size: 42, fallbackSeed: track.title),
            const SizedBox(width: 12),
            Expanded(child: _TitleBlock(track: track, error: player.error)),
            IconButton(
              onPressed: player.toggle,
              icon: Icon(
                player.playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                size: 38,
                color: AppColors.accent,
              ),
            ),
            IconButton(
              tooltip: '停止播放',
              onPressed: player.stop,
              iconSize: 24,
              color: AppColors.textSecondary,
              icon: const Icon(Icons.stop_rounded),
            ),
            IconButton(
              onPressed: player.next,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        if (player.isLive)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: _LiveBadge(),
          )
        else
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              min: 0,
              max: maxMs <= 0 ? 1 : maxMs,
              value: value,
              onChangeStart: (double v) => setState(() => _dragMs = v),
              onChanged:
                  maxMs <= 0 ? null : (double v) => setState(() => _dragMs = v),
              onChangeEnd: (double v) {
                player.seek(Duration(milliseconds: v.round()));
                setState(() => _dragMs = null);
              },
            ),
          ),
      ],
    );
  }

  static const TextStyle _timeStyle = TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  void _showQueue(BuildContext context, PlayerController player) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext context) {
        return Consumer<PlayerController>(
          builder: (BuildContext context, PlayerController p, _) {
            if (p.queue.isEmpty) {
              return const SizedBox(
                height: 160,
                child: Center(child: Text('队列是空的')),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: p.queue.length,
              itemBuilder: (BuildContext context, int index) {
                final Track item = p.queue[index];
                final bool active = index == p.index;
                return ListTile(
                  dense: true,
                  leading: CoverArt(
                    source: item.artwork,
                    size: 36,
                    fallbackSeed: item.title,
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: active ? AppColors.accent : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    item.artist ?? _sourceLabel(item.source),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: active
                      ? const Icon(Icons.graphic_eq_rounded,
                          size: 18, color: AppColors.accent)
                      : null,
                  onTap: () {
                    p.playAt(index);
                    Navigator.of(context).pop();
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// 直播流的占位条：没有确定时长，进度条无意义，只提示"正在直播"。
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFE2725B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '直播中',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _sourceLabel(TrackSource source) {
  switch (source) {
    case TrackSource.local:
      return '本地';
    case TrackSource.bilibili:
      return 'B站';
    case TrackSource.radio:
      return '电台';
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.track, this.error});

  final Track track;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final String? err = error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Text(
          err ?? track.artist ?? _sourceLabel(track.source),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            color: err != null ? const Color(0xFFE2725B) : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    if (player.buffering) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: player.playing ? '暂停' : '播放',
      onPressed: player.toggle,
      iconSize: 38,
      color: AppColors.accent,
      icon: Icon(
        player.playing
            ? Icons.pause_circle_filled_rounded
            : Icons.play_circle_fill_rounded,
      ),
    );
  }
}

class _ModeButtons extends StatelessWidget {
  const _ModeButtons({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final bool accentRepeat = player.repeat != LoopMode.off;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: '循环模式',
          onPressed: player.cycleRepeat,
          iconSize: 18,
          color: accentRepeat ? AppColors.accent : AppColors.textSecondary,
          icon: Icon(
            player.repeat == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
        ),
        IconButton(
          tooltip: '随机播放',
          onPressed: player.toggleShuffle,
          iconSize: 18,
          color: player.shuffle ? AppColors.accent : AppColors.textSecondary,
          icon: const Icon(Icons.shuffle_rounded),
        ),
      ],
    );
  }
}
