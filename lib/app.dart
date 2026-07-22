import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/ai_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/home_nav_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/practice_exam_provider.dart';
import 'providers/question_provider.dart';
import 'providers/reader_provider.dart';
import 'providers/theme_provider.dart';
import 'services/tray_service.dart';
import 'services/window_service.dart';
import 'views/auth/auth_gate.dart';
import 'views/common/page_transitions.dart';
import 'views/common/theme.dart';

export 'views/common/theme.dart';
export 'views/common/glass.dart';

/// 全平台 push 过渡：从右滑入 + 淡入（[SlidePageTransitionsBuilder]）。
final PageTransitionsTheme _pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    for (final p in TargetPlatform.values)
      p: const SlidePageTransitionsBuilder(),
  },
);

class StarHopeApp extends StatelessWidget {
  const StarHopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => QuestionBankProvider()),
        ChangeNotifierProvider(create: (_) => PracticeExamProvider()),
        ChangeNotifierProvider(create: (_) => AIProvider()),
        ChangeNotifierProvider(create: (_) => ReaderProvider()),
        ChangeNotifierProvider(create: (_) => HomeNavProvider()),
        ChangeNotifierProvider(create: (_) => PluginProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          title: 'StarHope',
          debugShowCheckedModeBanner: false,
          theme: StarHopeTheme.light().copyWith(
            pageTransitionsTheme: _pageTransitionsTheme,
          ),
          darkTheme: StarHopeTheme.dark().copyWith(
            pageTransitionsTheme: _pageTransitionsTheme,
          ),
          themeMode: theme.mode,
          home: const StarHopeRoot(),
          // 全局圆角裁剪 + F11 全屏快捷键
          builder: (context, child) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: KeyboardListener(
              focusNode: FocusNode(),
              autofocus: true,
              onKeyEvent: (e) {
                if (e is! KeyDownEvent) return;
                if (WindowService.isExamLocked) return; // 考试强制全屏中禁应用快捷键
                if (e.logicalKey == LogicalKeyboardKey.f11) {
                  WindowService.toggleFullscreen();
                  return;
                }
                if (_matchHotkey(
                    context.read<ThemeProvider>().lockHotkey, e)) {
                  context.read<AuthProvider>().logout();
                }
              },
              child: child!,
            ),
          ),
        ),
      ),
    );
  }
}

/// 应用根：负责初始化引导（主题/认证）并决定首屏
class StarHopeRoot extends StatefulWidget {
  const StarHopeRoot({super.key});
  @override
  State<StarHopeRoot> createState() => _StarHopeRootState();
}

class _StarHopeRootState extends State<StarHopeRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final theme = context.read<ThemeProvider>();
      final auth = context.read<AuthProvider>();
      await Future.wait([theme.init(), auth.bootstrap()]);
      await TrayService.instance.init(onLock: () {
        context.read<AuthProvider>().logout();
        WindowService.show();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return FadeThroughSwitcher<bool>(
      switchKey: ValueKey<bool>(auth.loading),
      child: auth.loading ? _bootstrapLoading() : const AuthGate(),
    );
  }

  /// 启动引导 loading（深蓝夜空，与登录页/加载页统一色调，避免浅→深跳变）。
  Widget _bootstrapLoading() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0b1026), Color(0xFF141a3a), Color(0xFF1a1140)],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8ea2ff)),
          ),
        ),
      ),
    );
  }
}

/// 比对应用内锁定热键（编码 'ctrl.m'：修饰键.键标签）
bool _matchHotkey(String encoded, KeyEvent e) {
  final dot = encoded.indexOf('.');
  if (dot < 0) return false;
  final mod = encoded.substring(0, dot);
  final keyLabel = encoded.substring(dot + 1).toUpperCase();
  final hk = HardwareKeyboard.instance;
  final modOk = mod == 'ctrl'
      ? hk.isControlPressed
      : mod == 'alt'
          ? hk.isAltPressed
          : mod == 'shift'
              ? hk.isShiftPressed
              : true;
  return modOk && e.logicalKey.keyLabel.toUpperCase() == keyLabel;
}
