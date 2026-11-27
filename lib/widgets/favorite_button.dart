import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../features/library/playlist_controller.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// 爱心按钮：点开歌单选择器；只要在任一歌单里就显示实心。
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.track,
    this.size = 20,
  });

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final PlaylistController lists = context.watch<PlaylistController>();
    final bool fav = lists.isFavorite(track.id);
    return IconButton(
      tooltip: fav ? '已加入歌单' : '加入歌单',
      visualDensity: VisualDensity.compact,
      onPressed: () => showPlaylistPicker(context, track),
      icon: Icon(
        fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: size,
        color: fav ? AppColors.accent : AppColors.textSecondary,
      ),
    );
  }
}

/// 歌单选择弹窗。已加入的歌单显示勾选，再点一次即移出。
Future<void> showPlaylistPicker(BuildContext context, Track track) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _PlaylistPickerSheet(track: track),
  );
}

class _PlaylistPickerSheet extends StatelessWidget {
  const _PlaylistPickerSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final PlaylistController ctrl = context.watch<PlaylistController>();
    final Set<String> joined = ctrl.playlistsOf(track.id);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.62,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '加入歌单',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: ctrl.playlists.length,
                itemBuilder: (BuildContext context, int index) {
                  final Playlist p = ctrl.playlists[index];
                  final bool inList = joined.contains(p.id);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      inList
                          ? Icons.favorite_rounded
                          : Icons.queue_music_rounded,
                      size: 20,
                      color: inList ? AppColors.accent : AppColors.textSecondary,
                    ),
                    title: Text(p.name, style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                      '${p.tracks.length} 首',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: inList
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: AppColors.accent)
                        : null,
                    onTap: () async {
                      if (inList) {
                        await ctrl.removeTrack(p.id, track.id);
                      } else {
                        await ctrl.addTrack(p.id, track);
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                inList
                                    ? '已从「${p.name}」移出'
                                    : '已加入「${p.name}」',
                              ),
                            ),
                          );
                      }
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_rounded, size: 20),
              title: const Text('新建歌单', style: TextStyle(fontSize: 13.5)),
              onTap: () async {
                final String? name = await _promptName(context);
                if (name == null || name.trim().isEmpty) return;
                final Playlist created = await ctrl.create(name);
                await ctrl.addTrack(created.id, track);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text('已加入「${created.name}」')),
                    );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptName(BuildContext context) async {
    final TextEditingController input = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('新建歌单', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
          onSubmitted: (String v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(input.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    input.dispose();
    return result;
  }
}
