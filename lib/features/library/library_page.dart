import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/player_controller.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/track.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/page_header.dart';
import 'library_controller.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LibraryController lib = context.watch<LibraryController>();
    final PlayerController player = context.watch<PlayerController>();
    final List<Track> tracks = lib.visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PageHeader(
          title: '本地音乐',
          subtitle: lib.tracks.isEmpty
              ? '导入文件夹后会自动读取标签与封面'
              : '${lib.tracks.length} 首 · ${lib.folders.length} 个文件夹',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: lib.scanning ? null : lib.addFiles,
              icon: const Icon(Icons.audio_file_outlined, size: 16),
              label: const Text('添加文件'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: lib.scanning ? null : lib.addFolder,
              icon: Icon(
                Platform.isAndroid
                    ? Icons.library_music_outlined
                    : Icons.create_new_folder_outlined,
                size: 16,
              ),
              label: Text(Platform.isAndroid ? '扫描手机音乐' : '添加文件夹'),
            ),
            IconButton(
              tooltip: '重新扫描',
              onPressed: lib.scanning ? null : lib.rescan,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: '播放全部',
              onPressed: tracks.isEmpty
                  ? null
                  : () => player.playAll(tracks),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: TextField(
            controller: _search,
            onChanged: lib.setQuery,
            decoration: InputDecoration(
              hintText: '搜索曲名、艺人、专辑',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _search.clear();
                        lib.setQuery('');
                      },
                    ),
            ),
          ),
        ),
        if (lib.scanning)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (lib.status != null)
          NoticeBanner(message: lib.status!, icon: Icons.folder_open_outlined),
        Expanded(
          child: tracks.isEmpty
              ? EmptyHint(
                  icon: Icons.library_music_outlined,
                  title: lib.tracks.isEmpty ? '还没有本地音乐' : '没有匹配的结果',
                  description: lib.tracks.isEmpty
                      ? (Platform.isAndroid
                          ? '点「扫描手机音乐」授权后，Listener 会扫描 Music、Download\n等目录里的 MP3 / FLAC / M4A 文件，并读取标签与封面。'
                          : '添加一个音乐文件夹，Listener 会扫描其中的 MP3 / FLAC / M4A 等文件，\n自动读取曲名、艺人和内嵌封面。')
                      : '换个关键词试试。',
                  actions: lib.tracks.isEmpty
                      ? <Widget>[
                          FilledButton.tonal(
                            onPressed: lib.addFolder,
                            child: Text(
                              Platform.isAndroid ? '扫描手机音乐' : '添加文件夹',
                            ),
                          ),
                        ]
                      : const <Widget>[],
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: tracks.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Track track = tracks[index];
                    return _TrackRow(
                      index: index,
                      track: track,
                      active: player.current?.id == track.id,
                      onTap: () => player.playAll(tracks, at: index),
                      onEnqueue: () {
                        player.enqueue(track);
                        _toast(context, '已加入队列');
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.active,
    required this.onTap,
    required this.onEnqueue,
  });

  final int index;
  final Track track;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEnqueue;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          color: _hover
              ? AppColors.surfaceHigh.withValues(alpha: 0.6)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                child: Text(
                  '${widget.index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.active
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              CoverArt(
                source: widget.track.artwork,
                size: 42,
                fallbackSeed: widget.track.title,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: widget.active
                            ? AppColors.accent
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (widget.track.artist != null) widget.track.artist!,
                        if (widget.track.album != null) widget.track.album!,
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
              if (widget.track.extra != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    widget.track.extra!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              Text(
                formatDuration(widget.track.duration),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              if (_hover)
                IconButton(
                  tooltip: '加入队列',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onEnqueue,
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                )
              else
                const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }
}
