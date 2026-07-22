import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/home_nav_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../common/bottom_nav_bar.dart';
import '../common/page_transitions.dart';
import '../common/theme.dart';
import '../common/window_title_bar.dart';
import 'ai_page.dart';
import 'learning_tools_page.dart';
import 'plugin_toolbox_page.dart';
import 'settings_page.dart';
import 'summary_page.dart';

/// 主界面外壳：底部圆边毛玻璃导航（5 项）+ 内容区（fade-through 切换）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _pages = const [
    LearningToolsPage(),
    PluginToolboxPage(),
    SummaryPage(),
    AIPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 窗口焦点监控（考试防作弊）
    final pe = context.read<PracticeExamProvider>();
    if (!pe.inExam) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      pe.reportFocusLost();
    } else if (state == AppLifecycleState.resumed) {
      pe.reportFocusGained();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<HomeNavProvider>();
    final index = nav.tab.index;
    return Scaffold(
      body: FrostedBackground(
        child: Column(
          children: [
            const WindowTitleBar(title: 'StarHope'),
            Expanded(
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: FadeThroughSwitcher<int>(
                        switchKey: ValueKey<int>(index),
                        child: _pages[index],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const StarBottomNav(),
          ],
        ),
      ),
    );
  }
}
