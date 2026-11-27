import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/player_bar.dart';
import '../bilibili/bili_page.dart';
import '../library/library_page.dart';
import '../radio/radio_page.dart';

/// 应用外壳：宽屏用侧边栏，窄屏用底部导航；播放栏常驻在内容与导航之间。
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  static const List<Widget> _pages = <Widget>[
    LibraryPage(),
    BiliPage(),
    RadioPage(),
  ];

  static const List<(IconData, IconData, String)> _destinations =
      <(IconData, IconData, String)>[
    (Icons.library_music_outlined, Icons.library_music_rounded, '本地'),
    (Icons.play_circle_outline_rounded, Icons.play_circle_fill_rounded, 'B站'),
    (Icons.radio_outlined, Icons.radio_rounded, '电台'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 920;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      if (wide) _buildRail(),
                      Expanded(
                        child: IndexedStack(
                          index: _index,
                          children: _pages,
                        ),
                      ),
                    ],
                  ),
                ),
                const PlayerBar(),
                if (!wide) _buildBottomBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRail() {
    return NavigationRail(
      selectedIndex: _index,
      onDestinationSelected: (int value) => setState(() => _index = value),
      labelType: NavigationRailLabelType.all,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.16),
      selectedIconTheme: const IconThemeData(color: AppColors.accent, size: 22),
      unselectedIconTheme:
          const IconThemeData(color: AppColors.textSecondary, size: 21),
      selectedLabelTextStyle: const TextStyle(
        fontSize: 11.5,
        color: AppColors.accent,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: const TextStyle(
        fontSize: 11.5,
        color: AppColors.textSecondary,
      ),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFE0A44A), Color(0xFFB9782C)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text(
            'L',
            style: TextStyle(
              color: Color(0xFF1A1510),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ),
      ),
      destinations: <NavigationRailDestination>[
        for (final (IconData unselected, IconData selected, String label)
            in _destinations)
          NavigationRailDestination(
            icon: Icon(unselected),
            selectedIcon: Icon(selected),
            label: Text(label),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (int value) => setState(() => _index = value),
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.16),
      height: 60,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: <NavigationDestination>[
        for (final (IconData unselected, IconData selected, String label)
            in _destinations)
          NavigationDestination(
            icon: Icon(unselected),
            selectedIcon: Icon(selected, color: AppColors.accent),
            label: label,
          ),
      ],
    );
  }
}
