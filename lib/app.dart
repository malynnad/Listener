import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'controllers/player_controller.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/bilibili/bili_controller.dart';
import 'features/library/library_controller.dart';
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
          create: (BuildContext ctx) =>
              BiliController(player: ctx.read<PlayerController>()),
        ),
        ChangeNotifierProvider<RadioController>(
          create: (BuildContext ctx) =>
              RadioController(player: ctx.read<PlayerController>()),
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
