import 'dart:ui';

import 'package:flutter/material.dart';

/// 主题 —— Material 3，毛玻璃风格，自动跟随系统明暗并可手动切换。
class StarHopeTheme {
  static const Color seed = Color(0xFF6366F1); // 靛蓝主色

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      // 提亮次要文字，避免深色毛玻璃背景上对比度不足
      onSurfaceVariant: const Color(0xFFDDE2EC),
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.06 : 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
    );
  }
}

/// 全局毛玻璃背景：渐变 + 模糊。
class FrostedBackground extends StatelessWidget {
  final Widget child;
  const FrostedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        // 渐变底色
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF1a1a2e),
                      const Color(0xFF16213e),
                      const Color(0xFF0f0f1e),
                    ]
                  : [
                      const Color(0xFFE0E7FF),
                      const Color(0xFFF5F3FF),
                      const Color(0xFFEDE9FE),
                    ],
            ),
          ),
        ),
        // 模糊光斑
        Positioned(
          top: -80,
          left: -60,
          child: _Blob(
            color: (isDark ? const Color(0xFF6366F1) : const Color(0xFF818CF8))
                .withValues(alpha: isDark ? 0.22 : 0.5),
            size: 260,
          ),
        ),
        Positioned(
          bottom: -100,
          right: -80,
          child: _Blob(
            color: (isDark ? const Color(0xFFEC4899) : const Color(0xFFF472B6))
                .withValues(alpha: isDark ? 0.16 : 0.35),
            size: 320,
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0.1, sigmaY: 0.1),
          child: child,
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
