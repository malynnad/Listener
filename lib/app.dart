import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'controllers/player_controller.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/bilibili/bili_controller.dart';
import 'features/library/library_controller.dart';
import 'features/library/playlist_controller.dart';
import 'features/radio/radio_controller.dart';
import 'features/shell/shell_page.dart';

class ListenerApp extends StatelessWidget {
  const ListenerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<PlayerController>(
          create: (_) => PlayerController(),
        ),
        ChangeNotifierProvider<LibraryController>(
          create: (_) => LibraryController(),
        ),
        ChangeNotifierProvider<BiliController>(
          create: (BuildContext ctx) => BiliController(
            player: ctx.read<PlayerController>(),
            // 下载落到 Music 后让媒体库重扫一次，曲子能立刻出现在列表里。
            onDownloaded: () => ctx.read<LibraryController>().rescan(),
          ),
        ),
        ChangeNotifierProvider<RadioController>(
          create: (BuildContext ctx) =>
              RadioController(player: ctx.read<PlayerController>()),
        ),
        // 歌单要能把 B 站曲目重新解析成可播直链，所以放在 BiliController 之后。
        ChangeNotifierProvider<PlaylistController>(
          create: (BuildContext ctx) => PlaylistController(
            player: ctx.read<PlayerController>(),
            resolveBili: (String bvid) =>
                ctx.read<BiliController>().resolveBvid(bvid),
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const ShellPage(),
      ),
    );
  }
}
