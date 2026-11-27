import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/page_header.dart';
import 'playlist_controller.dart';

/// 歌单详情：本地曲目与 B 站曲目混排，点任意一首开始播放。
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final PlaylistController ctrl = context.watch<PlaylistController>();
    final Playlist? playlist = ctrl.byId(playlistId);

    if (playlist == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.surface),
        body: const Center(child: Text('这个歌单已被删除')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 6),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${playlist.tracks.length} 首 · 本地与 B 站混排',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '播放全部',
                    onPressed: playlist.tracks.isEmpty
                        ? null
                        : () => ctrl.playPlaylist(playlist.id),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    tooltip: '删除歌单',
                    onPressed: () => _confirmDelete(context, ctrl, playlist),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
            if (ctrl.preparing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (ctrl.error != null)
              NoticeBanner(message: ctrl.error!, icon: Icons.error_outline),
            Expanded(
              child: playlist.tracks.isEmpty
                  ? const EmptyHint(
                      icon: Icons.favorite_border_rounded,
                      title: '歌单还是空的',
                      description: '在媒体库或搜索结果里点爱心，就能把歌加进来。',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: playlist.tracks.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Track track = playlist.tracks[index];
                        return _PlaylistRow(
                          index: index,
                          track: track,
                          onTap: () =>
                              ctrl.playPlaylist(playlist.id, at: index),
                          onRemove: () =>
                              ctrl.removeTrack(playlist.id, track.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PlaylistController ctrl,
    Playlist playlist,
  ) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('删除歌单', style: TextStyle(fontSize: 16)),
        content: Text('「${playlist.name}」及其中的 ${playlist.tracks.length} 首记录会被删除，本地音频文件不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await ctrl.remove(playlist.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.index,
    required this.track,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bool fromBili = track.source == TrackSource.bilibili;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            CoverArt(
              source: track.artwork,
              size: 42,
              fallbackSeed: track.title,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      if (track.artist != null && track.artist!.isNotEmpty)
                        track.artist!,
                      if (fromBili) 'B站' else '本地',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatDuration(track.duration),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '移出歌单',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.favorite_rounded,
                  size: 18, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
