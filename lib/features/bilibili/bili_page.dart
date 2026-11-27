import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/track.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/favorite_button.dart';
import '../../widgets/page_header.dart';
import 'bili_controller.dart';
import 'bili_models.dart';
import 'login_sheet.dart';

class BiliPage extends StatefulWidget {
  const BiliPage({super.key});

  @override
  State<BiliPage> createState() => _BiliPageState();
}

class _BiliPageState extends State<BiliPage> {
  final TextEditingController _search = TextEditingController();
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = context.read<BiliController>().messages.listen((String message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BiliController bili = context.watch<BiliController>();
    final List<BiliSearchResult> results = bili.results;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PageHeader(
          title: '搜索',
          subtitle: bili.isLoggedIn
              ? '已登录 ${bili.user?.name ?? ''} · 可获取账号权限内的最高码率'
              : '登录后才能搜索 · 未登录请求会被 B 站风控拦成空结果',
          actions: <Widget>[
            IconButton(
              tooltip: '打开下载目录',
              onPressed: bili.openDownloadFolder,
              icon: const Icon(Icons.folder_outlined),
            ),
            _AccountChip(bili: bili),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (String value) => _submitSearch(bili, value),
                  decoration: InputDecoration(
                    hintText: bili.isLoggedIn
                        ? '搜索歌曲、翻唱、现场、纯音乐…'
                        : '登录后可搜索',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () => _submitSearch(bili, _search.text),
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        if (bili.searching)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (bili.error != null)
          NoticeBanner(
            message: bili.error!,
            icon: Icons.error_outline,
          ),
        Expanded(
          child: results.isEmpty
              ? EmptyHint(
                  icon: Icons.travel_explore_rounded,
                  title: bili.isLoggedIn ? '从 B 站找歌' : '先登录，再搜索',
                  description: bili.isLoggedIn
                      ? '输入关键词搜索视频，Listener 会抽取其中的音轨直接播放，\n并可按账号权限下载为本地文件。'
                      : '未登录的搜索请求会被 B 站风控拦截，只会返回空结果，\n所以这里要求先扫码登录。登录后即可搜索、播放并下载。',
                  actions: <Widget>[
                    if (!bili.isLoggedIn)
                      FilledButton.tonal(
                        onPressed: () => _openLogin(bili),
                        child: const Text('扫码登录'),
                      ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: results.length,
                  itemBuilder: (BuildContext context, int index) {
                    final BiliSearchResult item = results[index];
                    return _BiliRow(
                      item: item,
                      stored: bili.stubOf(item),
                      progress: bili.progress[item.bvid],
                      downloaded: bili.downloads.containsKey(item.bvid),
                      onPlay: () => bili.play(item),
                      onDownload: () => bili.download(item),
                      onEnqueue: () => bili.enqueue(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 搜索入口统一走这里：未登录先引导登录，登录成功后自动接着搜。
  void _submitSearch(BiliController bili, String keyword) {
    final String kw = keyword.trim();
    if (!bili.isLoggedIn) {
      _openLogin(bili, pendingKeyword: kw);
      return;
    }
    if (kw.isEmpty) return;
    bili.search(kw);
  }

  Future<void> _openLogin(
    BiliController bili, {
    String pendingKeyword = '',
  }) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext context) => LoginSheet(
        auth: bili.auth,
        onSuccess: bili.refreshUser,
      ),
    );
    if (bili.isLoggedIn && pendingKeyword.isNotEmpty) {
      await bili.search(pendingKeyword);
    }
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.bili});

  final BiliController bili;

  @override
  Widget build(BuildContext context) {
    if (!bili.isLoggedIn) {
      return FilledButton.tonalIcon(
        onPressed: () async {
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            showDragHandle: true,
            builder: (BuildContext context) => LoginSheet(
              auth: bili.auth,
              onSuccess: bili.refreshUser,
            ),
          );
        },
        icon: const Icon(Icons.qr_code_2_rounded, size: 16),
        label: const Text('扫码登录'),
      );
    }

    final BiliUser? user = bili.user;
    final String? face = user?.face;
    return PopupMenuButton<String>(
      tooltip: '账号',
      color: AppColors.surfaceHigh,
      onSelected: (String value) {
        if (value == 'logout') bili.logout();
      },
      itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'logout', child: Text('退出登录')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.border,
              backgroundImage: (face != null && face.startsWith('http'))
                  ? NetworkImage(face)
                  : null,
              child: face == null
                  ? const Icon(Icons.person, size: 14)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              user?.name.isNotEmpty == true ? user!.name : '已登录',
              style: const TextStyle(fontSize: 12.5),
            ),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _BiliRow extends StatefulWidget {
  const _BiliRow({
    required this.item,
    required this.stored,
    required this.progress,
    required this.downloaded,
    required this.onPlay,
    required this.onDownload,
    required this.onEnqueue,
  });

  final BiliSearchResult item;

  /// 加入歌单时保存的占位曲目（只带元数据，播放时再解析直链）。
  final Track stored;
  final double? progress;
  final bool downloaded;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final VoidCallback onEnqueue;

  @override
  State<_BiliRow> createState() => _BiliRowState();
}

class _BiliRowState extends State<_BiliRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final BiliSearchResult item = widget.item;
    final double? progress = widget.progress;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onPlay,
        child: Container(
          color: _hover
              ? AppColors.surfaceHigh.withValues(alpha: 0.6)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: <Widget>[
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CoverArt(
                    source: item.cover,
                    size: 56,
                    fallbackSeed: item.title,
                  ),
                  if (_hover)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      <String>[
                        item.author,
                        item.durationText,
                        if (item.playCount > 0)
                          '${formatCount(item.playCount)}播放',
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
              const SizedBox(width: 8),
              FavoriteButton(track: widget.stored, size: 20),
              if (progress != null)
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress < 0 ? null : progress.clamp(0.0, 1.0),
                    ),
                  ),
                )
              else if (widget.downloaded)
                const IconButton(
                  tooltip: '已下载',
                  visualDensity: VisualDensity.compact,
                  onPressed: null,
                  icon: Icon(Icons.download_done_rounded,
                      size: 20, color: AppColors.accent),
                )
              else
                IconButton(
                  tooltip: '下载音频',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_rounded, size: 20),
                ),
              IconButton(
                tooltip: '加入队列',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onEnqueue,
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
