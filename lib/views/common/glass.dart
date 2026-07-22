import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 毛玻璃卡片：半透明 + BackdropFilter 模糊 + 渐变边框。
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final Color? surfaceColor; // 传入则用纯实色背景（覆盖默认玻璃 tint+渐变），用于需要高对比的卡片

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.blur = 16,
    this.borderRadius,
    this.onTap,
    this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(20);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: surfaceColor ??
                  (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: isDark ? 0.08 : 0.04),
              borderRadius: radius,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.5),
              ),
              gradient: surfaceColor == null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.10 : 0.25),
                        Colors.white.withValues(alpha: isDark ? 0.02 : 0.05),
                      ],
                    )
                  : null,
            ),
            padding: padding ?? const EdgeInsets.all(16),
            child: onTap == null
                ? child
                : InkWell(onTap: onTap, child: child),
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃应用栏
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AppBar(
          leading: leading,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          actions: actions,
          backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 来源标签
class SourceBadge extends StatelessWidget {
  final String? nickname;
  final String? authorId;
  final VoidCallback? onTap;
  const SourceBadge({super.key, this.nickname, this.authorId, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (nickname == null || nickname!.isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_circle,
                size: 13,
                color: Theme.of(context).colorScheme.onTertiaryContainer),
            const SizedBox(width: 4),
            Text(
              '来源: $nickname',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部固定签名栏
class PoweredFooter extends StatelessWidget {
  const PoweredFooter({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      child: Text(
        AppConstants.poweredBy,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 空状态占位
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
