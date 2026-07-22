import 'dart:math';

import 'package:flutter/material.dart';

/// 灵动按钮：悬停时显示星空环绕高亮 + 轻微缩放；按下时回弹。
///
/// 用于应用中的主要操作按钮，提供统一的"灵动"交互反馈。
class StarryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool expanded;
  final bool isLoading;

  const StarryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expanded = true,
    this.isLoading = false,
  });

  @override
  State<StarryButton> createState() => _StarryButtonState();
}

class _StarryButtonState extends State<StarryButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  bool _press = false;
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = widget.color ?? cs.primary;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hover = true);
        _ctl.forward();
      },
      onExit: (_) {
        setState(() => _hover = false);
        _ctl.reverse();
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _press = true),
        onTapUp: (_) {
          setState(() => _press = false);
          widget.onPressed?.call();
        },
        onTapCancel: () => setState(() => _press = false),
        child: AnimatedScale(
          scale: _press ? 0.96 : (_hover ? 1.03 : 1.0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: _buildButton(context, base),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, Color base) {
    final cs = Theme.of(context).colorScheme;
    final disabled = widget.onPressed == null && !widget.isLoading;
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, child) {
        final v = Curves.easeOut.transform(_ctl.value);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 星空环绕光晕（悬停时）
            if (v > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _AuraPainter(v,
                        color: base, dark: Theme.of(context).brightness == Brightness.dark),
                  ),
                ),
              ),
            // 按钮主体
            Container(
              constraints: widget.expanded
                  ? const BoxConstraints(minWidth: double.infinity)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: disabled
                      ? [cs.onSurface.withValues(alpha: 0.2), cs.onSurface.withValues(alpha: 0.15)]
                      : [base, Color.lerp(base, Colors.white, 0.18)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: base.withValues(alpha: disabled ? 0 : 0.35 + v * 0.3),
                    blurRadius: 10 + v * 18,
                    offset: Offset(0, 4 + v * 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.isLoading) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (widget.icon != null) ...[
                    Icon(widget.icon,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(widget.label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 悬停光环：旋转的星点 + 柔光，强度随 [progress]（0..1）。
class _AuraPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool dark;
  _AuraPainter(this.progress, {required this.color, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    // 外圈柔光
    final glow = Paint()
      ..color = color.withValues(alpha: progress * 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy),
            width: size.width + 16,
            height: size.height + 16),
        const Radius.circular(18),
      ),
      glow,
    );
    // 围绕的星点（12 颗）
    const count = 12;
    for (var i = 0; i < count; i++) {
      final baseAngle = i / count * 2 * pi;
      final wobble = sin((progress * 4 * pi) + i) * 6;
      final radius = max(size.width, size.height) / 2 + 12 + wobble;
      final angle = baseAngle + progress * 1.2;
      final x = cx + cos(angle) * radius;
      final y = cy + sin(angle) * (size.height / 2 + 10) * 0.6;
      final twinkle = (sin(progress * 6 * pi + i) + 1) / 2;
      final a = progress * (0.4 + twinkle * 0.6);
      canvas.drawCircle(
          Offset(x, y),
          1.3 + twinkle,
          Paint()..color = (i % 2 == 0 ? Colors.white : color).withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(covariant _AuraPainter old) => old.progress != progress;
}
