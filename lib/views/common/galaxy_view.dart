import 'dart:math';

import 'package:flutter/material.dart';

/// 银河流动动画：斜向银河亮带 + 密集星点 + 沿带流动的亮光。
///
/// 纯本地 CustomPaint 绘制（不联网）。性能：星点按尺寸预生成并缓存，
/// 每帧只更新依赖时间的闪烁与流光位置。
class GalaxyView extends StatefulWidget {
  final Color? baseColor;
  const GalaxyView({super.key, this.baseColor});

  @override
  State<GalaxyView> createState() => _GalaxyViewState();
}

/// 一颗银河星点（带坐标系：u 沿带方向，v 沿法线方向）。
class _GStar {
  const _GStar(this.u, this.v, this.r, this.phase, this.bright);
  final double u, v, r, phase;
  final bool bright;
}

class _GalaxyViewState extends State<GalaxyView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  Size _size = Size.zero;
  List<_GStar> _stars = const [];

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _regen(Size size) {
    if (size == _size && _stars.isNotEmpty) return;
    _size = size;
    final rnd = Random(7);
    final bandH = size.height * 0.55;
    final halfLen = size.width * 1.2;
    final sigma = bandH / 5;
    // 近似高斯：星点向带中心集中
    double gauss() =>
        (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * sigma;
    final count = (size.width * size.height / 2500).clamp(80, 240).toInt();
    _stars = List.generate(
        count,
        (_) {
          final bright = rnd.nextDouble() < 0.18;
          return _GStar(
            (rnd.nextDouble() * 2 - 1) * halfLen,
            gauss(),
            bright ? rnd.nextDouble() * 1.2 + 0.8 : rnd.nextDouble() * 0.9 + 0.3,
            rnd.nextDouble() * 2 * pi,
            bright,
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ?? const Color(0xFF9fb0ff);
    return LayoutBuilder(
      builder: (context, c) {
        _regen(Size(c.maxWidth, c.maxHeight));
        return AnimatedBuilder(
          animation: _ctl,
          builder: (_, __) {
            return CustomPaint(
              size: Size.infinite,
              painter: _GalaxyPainter(_ctl.value,
                  baseColor: baseColor, stars: _stars, size: _size),
            );
          },
        );
      },
    );
  }
}

class _GalaxyPainter extends CustomPainter {
  final double t;
  final Color baseColor;
  final List<_GStar> stars;
  final Size size;
  _GalaxyPainter(this.t,
      {required this.baseColor, required this.stars, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final w = size.width, h = size.height;
    const theta = -0.32; // 银河带倾角
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(theta);
    final halfLen = w * 1.2;
    final bandH = h * 0.55;

    // 银河亮带（中心亮、边缘渐隐 + 模糊）
    final bandRect =
        Rect.fromCenter(center: Offset.zero, width: halfLen * 2, height: bandH);
    final bandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          baseColor.withValues(alpha: 0),
          baseColor.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.10),
          baseColor.withValues(alpha: 0.14),
          baseColor.withValues(alpha: 0),
        ],
      ).createShader(bandRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawRect(bandRect, bandPaint);

    // 星点（带坐标系，已预生成）
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final s in stars) {
      final tw = (sin(t * 2 * pi + s.phase) + 1) / 2;
      starPaint.color = (s.bright ? Colors.white : baseColor)
          .withValues(alpha: (s.bright ? 0.5 : 0.3) + tw * 0.5);
      canvas.drawCircle(Offset(s.u, s.v), s.r, starPaint);
    }

    // 沿带流动的亮光（两道，不同速度循环）
    for (var k = 0; k < 2; k++) {
      final period = halfLen * 2;
      final u = ((t * halfLen * (k == 0 ? 0.35 : 0.22) + k * halfLen) % period) -
          halfLen;
      final flowRect =
          Rect.fromCenter(center: Offset(u, 0), width: 180, height: bandH * 0.9);
      final flowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.35),
            baseColor.withValues(alpha: 0.12),
            baseColor.withValues(alpha: 0),
          ],
        ).createShader(flowRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
      canvas.drawRect(flowRect, flowPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter old) => old.t != t;
}
