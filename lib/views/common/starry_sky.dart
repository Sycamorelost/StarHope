import 'dart:math';

import 'package:flutter/material.dart';

/// 流星星空动画背景。
///
/// 静态星点闪烁 + 随机划过的流星，纯 CustomPainter 绘制。
/// 性能：星点坐标与流星起点按尺寸预生成并缓存（仅尺寸变化时重算），
/// 每帧只更新依赖时间的闪烁 alpha 与流星进度，复用 Paint 对象。
class StarrySky extends StatefulWidget {
  final Color? baseColor;
  const StarrySky({super.key, this.baseColor});

  @override
  State<StarrySky> createState() => _StarrySkyState();
}

/// 一颗静态星点的预生成数据（位置、半径固定，仅闪烁 alpha 随时间）。
class _Star {
  const _Star(this.x, this.y, this.r);
  final double x, y, r;
}

class _StarrySkyState extends State<StarrySky>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  // 预生成缓存：仅在绘制尺寸变化时重新生成
  Size _size = Size.zero;
  List<_Star> _stars = const [];
  List<double> _meteorStartX = const [];

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// 按尺寸预生成星点与流星起点（固定种子 → 位置稳定；尺寸不变则跳过）。
  void _regen(Size size) {
    if (size == _size && _stars.isNotEmpty) return;
    _size = size;
    final rnd = Random(42); // 固定种子保证星点位置稳定
    final starCount = (size.width * size.height / 6000).clamp(20, 90).toInt();
    _stars = List.generate(
        starCount,
        (_) => _Star(
              rnd.nextDouble() * size.width,
              rnd.nextDouble() * size.height,
              rnd.nextDouble() * 1.4 + 0.3,
            ));
    _meteorStartX = List.generate(
        3, (_) => rnd.nextDouble() * size.width * 0.5 + size.width * 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.baseColor ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, c) {
        _regen(Size(c.maxWidth, c.maxHeight));
        return AnimatedBuilder(
          animation: _ctl,
          builder: (_, __) {
            return CustomPaint(
              size: Size.infinite,
              painter: _StarryPainter(_ctl.value,
                  baseColor: baseColor,
                  stars: _stars,
                  meteorStartX: _meteorStartX),
            );
          },
        );
      },
    );
  }
}

class _StarryPainter extends CustomPainter {
  final double t;
  final Color baseColor;
  final List<_Star> stars;
  final List<double> meteorStartX;
  _StarryPainter(this.t,
      {required this.baseColor,
      required this.stars,
      required this.meteorStartX});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // 静态星点（闪烁，坐标已预生成）
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < stars.length; i++) {
      final s = stars[i];
      final tw = (sin((t * 2 * pi) + i) + 1) / 2; // 0..1 闪烁
      final alpha = (0.25 + tw * 0.6).clamp(0.0, 1.0);
      starPaint.color = baseColor.withValues(alpha: alpha.toDouble());
      canvas.drawCircle(Offset(s.x, s.y), s.r, starPaint);
    }

    // 流星：3 条，固定起点，从右上向左下周期性划过
    const dirX = -0.7, dirY = 0.71;
    const tailLen = 70.0;
    const segments = 10;
    final segPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0; // 0..1 周期
      if (phase > 0.80) continue; // 仅前 80% 时间可见
      final p = phase / 0.80; // 0..1 进度
      final startX = meteorStartX[i];
      const startY = -20.0;
      final travel = (w + h) * 0.6 * p;
      final hx = startX + dirX * travel;
      final hy = startY + dirY * travel;
      final fade = (1 - p).clamp(0.0, 1.0);
      for (var s = 0; s < segments; s++) {
        final f0 = s / segments;
        final f1 = (s + 1) / segments;
        final p0 = Offset(hx - dirX * tailLen * f0, hy - dirY * tailLen * f0);
        final p1 = Offset(hx - dirX * tailLen * f1, hy - dirY * tailLen * f1);
        final a = fade * (1 - f0) * 0.9;
        segPaint
          ..color = (s == 0 ? Colors.white : baseColor).withValues(alpha: a)
          ..strokeWidth = 1.8 * (1 - f0 * 0.6);
        canvas.drawLine(p0, p1, segPaint);
      }
      segPaint.color = Colors.white.withValues(alpha: fade);
      canvas.drawCircle(Offset(hx, hy), 1.8, segPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarryPainter old) => old.t != t;
}
