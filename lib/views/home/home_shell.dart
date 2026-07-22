import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_nav_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../../providers/question_provider.dart';
import '../../providers/reader_provider.dart';
import '../common/glass.dart';
import '../common/theme.dart';
import '../common/window_title_bar.dart';
import 'ai_page.dart';
import 'exam_page.dart';
import 'practice_page.dart';
import 'question_bank_page.dart';
import 'reader_page.dart';
import 'settings_page.dart';
import 'summary_page.dart';
import 'wrong_book_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  bool _refreshing = false;
  final _pages = const [
    SummaryPage(),
    QuestionBankPage(),
    WrongBookPage(),
    PracticePage(),
    ExamPage(),
    ReaderPage(),
    AIPage(),
    SettingsPage(),
  ];

  final _destinations = const [
    (icon: Icons.dashboard_outlined, label: '摘要'),
    (icon: Icons.library_books_outlined, label: '题库'),
    (icon: Icons.error_outline, label: '错题本'),
    (icon: Icons.fitness_center_outlined, label: '练习'),
    (icon: Icons.school_outlined, label: '考试'),
    (icon: Icons.menu_book_outlined, label: '阅读'),
    (icon: Icons.smart_toy_outlined, label: 'AI'),
    (icon: Icons.settings_outlined, label: '我的'),
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

  /// 全局刷新：重载所有 Provider 数据 + 通知订阅方（如摘要重算错题数）。
  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final qb = context.read<QuestionBankProvider>();
      final pe = context.read<PracticeExamProvider>();
      final rd = context.read<ReaderProvider>();
      final ai = context.read<AIProvider>();
      await Future.wait([
        qb.load(),
        pe.loadHistory(),
        pe.loadRulesAndResults(),
        rd.load(),
        ai.load(),
      ]);
      if (!mounted) return;
      context.read<HomeNavProvider>().bumpRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已刷新，数据已全局同步'), duration: Durations.short2));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
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
                      child: isWide ? _wideLayout() : _narrowLayout(),
                    ),
                    const PoweredFooter(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideLayout() {
    final auth = context.watch<AuthProvider>();
    final nav = context.watch<HomeNavProvider>();
    final index = nav.tab.index;
    return Row(
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: NavigationRail(
              minWidth: 72,
              selectedIndex: index,
              onDestinationSelected: (i) => nav.switchTo(HomeTab.values[i]),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Tooltip(
                  message: '刷新·全局同步数据',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _refreshing ? null : _refreshAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _refreshing
                                ? Icons.sync
                                : Icons.refresh,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _refreshing ? '同步中' : '刷新',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color:
                                    Theme.of(context).colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        (auth.user?.nickname ?? '?')
                            .characters
                            .first
                            .toUpperCase(),
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer),
                      ),
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: _pages[index]),
      ],
    );
  }

  Widget _narrowLayout() {
    final nav = context.watch<HomeNavProvider>();
    final index = nav.tab.index;
    return Column(
      children: [
        Expanded(child: _pages[index]),
        NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => nav.switchTo(HomeTab.values[i]),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.icon),
                label: d.label,
              ),
          ],
        ),
      ],
    );
  }
}
