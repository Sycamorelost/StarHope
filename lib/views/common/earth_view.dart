import 'dart:math';

import 'package:flutter/material.dart';

/// 静态地球（不自转）：精致风格化地球——多层大气光晕 + 边缘散射 rim light +
/// 深邃海洋（镜面反光）+ 气候带陆地渐变（极地白 / 温带绿 / 热带棕，随纬度变色）
/// + 极地冰盖 + 半透明云层 + 晨昏阴影；旁边周期划过的流星。
///
/// 纯本地 CustomPaint 绘制（不联网、无新依赖）。陆地经纬度为 const 固定数据，
/// 仅按尺寸缓存半径/中心与流星起点；地球静止，每帧重绘仅为驱动流星动画。
class EarthView extends StatefulWidget {
  final Color? baseColor;
  const EarthView({super.key, this.baseColor});

  @override
  State<EarthView> createState() => _EarthViewState();
}

/// 一个经纬度顶点（lon°∈[-180,180]，lat°∈[-90,90]，本初子午线 lon=0）。
class _GeoPt {
  final double lon, lat;
  const _GeoPt(this.lon, this.lat);
}

/// 一块大陆：外环多边形顶点（顺时针）。统一用气候带渐变着色，无需自带颜色。
class _Continent {
  final List<_GeoPt> pts;
  const _Continent(this.pts);
}

/// 一团云：中心经纬度 + 东西/南北跨度（度）。
class _Cloud {
  final double lon, lat, w, h;
  const _Cloud(this.lon, this.lat, this.w, this.h);
}

/// 固定展示角度（让亚欧-非洲-印度洋这面陆地最丰富的半球朝前）。
const _rotationDeg = 25.0;

/// 风格化大陆数据（手工粗略经纬度，非照抄地图，仅求辨识度）。南极走圆冠特殊处理。
const _continents = <_Continent>[
  // 亚欧大陆
  _Continent([
    _GeoPt(-10, 55), _GeoPt(15, 70), _GeoPt(60, 72), _GeoPt(110, 73),
    _GeoPt(140, 66), _GeoPt(142, 54), _GeoPt(128, 42), _GeoPt(112, 30),
    _GeoPt(92, 24), _GeoPt(74, 26), _GeoPt(52, 30), _GeoPt(32, 37),
    _GeoPt(14, 45), _GeoPt(-9, 48),
  ]),
  // 非洲
  _Continent([
    _GeoPt(-17, 30), _GeoPt(10, 34), _GeoPt(33, 31), _GeoPt(44, 12),
    _GeoPt(51, 11), _GeoPt(40, -5), _GeoPt(38, -20), _GeoPt(28, -33),
    _GeoPt(16, -34), _GeoPt(9, -5), _GeoPt(-10, 8), _GeoPt(-16, 20),
  ]),
  // 北美
  _Continent([
    _GeoPt(-165, 65), _GeoPt(-140, 70), _GeoPt(-100, 72), _GeoPt(-70, 60),
    _GeoPt(-58, 48), _GeoPt(-70, 42), _GeoPt(-82, 30), _GeoPt(-100, 26),
    _GeoPt(-115, 30), _GeoPt(-128, 38), _GeoPt(-145, 52), _GeoPt(-162, 58),
  ]),
  // 南美
  _Continent([
    _GeoPt(-78, 10), _GeoPt(-62, 8), _GeoPt(-52, 0), _GeoPt(-42, -8),
    _GeoPt(-36, -22), _GeoPt(-44, -34), _GeoPt(-58, -40), _GeoPt(-72, -42),
    _GeoPt(-78, -25), _GeoPt(-80, -5),
  ]),
  // 大洋洲
  _Continent([
    _GeoPt(114, -18), _GeoPt(133, -12), _GeoPt(145, -14), _GeoPt(153, -26),
    _GeoPt(143, -38), _GeoPt(135, -35), _GeoPt(122, -34), _GeoPt(114, -28),
  ]),
  // 格陵兰（高纬，渐变自动偏冰雪白）
  _Continent([
    _GeoPt(-50, 82), _GeoPt(-20, 80), _GeoPt(-15, 70), _GeoPt(-35, 62),
    _GeoPt(-52, 72), _GeoPt(-55, 80),
  ]),
];

/// 静态云层分布（经纬度 + 跨度度数）。
const _clouds = <_Cloud>[
  _Cloud(-40, 12, 42, 13),
  _Cloud(0, 5, 40, 12),
  _Cloud(28, 38, 32, 12),
  _Cloud(70, 28, 38, 14),
  _Cloud(105, 8, 36, 13),
  _Cloud(48, -12, 30, 11),
  _Cloud(125, -28, 30, 12),
  _Cloud(-60, 45, 34, 13),
];

class _EarthViewState extends State<EarthView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  Size _size = Size.zero;
  double _r = 0;
  Offset _c = Offset.zero;
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

  void _regen(Size size) {
    if (size == _size) return;
    _size = size;
    _r = min(size.width, size.height) * 0.42;
    _c = Offset(size.width / 2, size.height / 2);
    final rnd = Random(11);
    _meteorStartX = List.generate(
        3, (_) => rnd.nextDouble() * size.width * 0.5 + size.width * 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ?? const Color(0xFF8ea2ff);
    return LayoutBuilder(
      builder: (context, c) {
        _regen(Size(c.maxWidth, c.maxHeight));
        return AnimatedBuilder(
          animation: _ctl,
          builder: (_, __) {
            return CustomPaint(
              size: Size.infinite,
              painter: _EarthPainter(_ctl.value,
                  c: _c,
                  r: _r,
                  size: _size,
                  baseColor: baseColor,
                  meteorStartX: _meteorStartX),
            );
          },
        );
      },
    );
  }
}

class _EarthPainter extends CustomPainter {
  final double t;
  final Offset c;
  final double r;
  final Size size;
  final Color baseColor;
  final List<double> meteorStartX;

  _EarthPainter(this.t,
      {required this.c,
      required this.r,
      required this.size,
      required this.baseColor,
      required this.meteorStartX});

  /// 相对经度（固定展示角），归一化到 [-180,180]。
  double _relLon(double lon) {
    final rel = lon + _rotationDeg;
    return ((rel + 180) % 360 + 360) % 360 - 180;
  }

  /// 球面正交投影；背面（|relLon|≥90）的点 clamp 到边缘 ±89.5°，贴边模拟被球面遮挡。
  Offset _project(double lon, double lat) {
    var rel = _relLon(lon);
    if (rel > 89.5) rel = 89.5;
    if (rel < -89.5) rel = -89.5;
    final latR = lat * pi / 180;
    final relR = rel * pi / 180;
    return Offset(c.dx + r * cos(latR) * sin(relR), c.dy - r * sin(latR));
  }

  int _subdiv(double dlon) => (dlon.abs() / 10).ceil().clamp(0, 18);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (r <= 0) return;
    final w = size.width, h = size.height;
    final earthRect = Rect.fromCircle(center: c, radius: r);

    // 1. 外层大气光晕（盘外柔光）
    final haloRect = Rect.fromCircle(center: c, radius: r * 1.4);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF7FC6F2).withValues(alpha: 0),
          const Color(0xFF5AA8E8).withValues(alpha: 0.30),
          const Color(0xFF5AA8E8).withValues(alpha: 0),
        ],
        stops: const [0.0, 0.68, 1.0],
      ).createShader(haloRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawRect(haloRect, haloPaint);

    // 2. 海洋球体（深邃径向渐变，光源偏左上）
    final oceanPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.4, -0.4),
        radius: 0.95,
        colors: [
          Color(0xFF2E72B8),
          Color(0xFF16406A),
          Color(0xFF0A2340),
        ],
      ).createShader(earthRect);
    canvas.drawCircle(c, r, oceanPaint);

    canvas.save();
    canvas.clipPath(Path()..addOval(earthRect));

    // 3. 海洋镜面反光（左上亮斑）
    final specPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.4),
        radius: 0.42,
        colors: [
          Colors.white.withValues(alpha: 0.32),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(earthRect);
    canvas.drawCircle(c, r, specPaint);

    // 4. 陆地（气候带渐变：极地白 / 温带绿 / 热带棕，随纬度自然变色）
    final landPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFD8E2E6), // 北极冰
          Color(0xFF4E9052), // 北温带绿
          Color(0xFF7E8A3C), // 热带 橄榄/沙
          Color(0xFF4E9052), // 南温带绿
          Color(0xFFD8E2E6), // 南极冰
        ],
        stops: [0.0, 0.22, 0.5, 0.78, 1.0],
      ).createShader(earthRect);
    for (final cont in _continents) {
      _drawContinent(canvas, cont, landPaint);
    }

    // 5. 南极冰盖圆冠（lat<-65 的球底区域）
    _drawAntarctica(canvas);

    // 6. 云层（静态半透明白，柔化）
    final cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.50)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final cl in _clouds) {
      if (_relLon(cl.lon).abs() >= 90) continue;
      final center = _project(cl.lon, cl.lat);
      final latR = cl.lat * pi / 180;
      final ew = r * (cl.w * pi / 180) * cos(latR);
      final eh = r * (cl.h * pi / 180);
      canvas.drawOval(
          Rect.fromCenter(center: center, width: ew, height: eh), cloudPaint);
    }

    // 7. 晨昏阴影（右下暗，增强球感）
    final termPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withValues(alpha: 0),
          Colors.black.withValues(alpha: 0.50),
        ],
      ).createShader(earthRect);
    canvas.drawCircle(c, r, termPaint);

    // 8. 边缘大气散射 rim light（青色辉光环，地球标志性特征）
    final rimPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFA8DDFF).withValues(alpha: 0),
          const Color(0xFFA8DDFF).withValues(alpha: 0),
          const Color(0xFFA8DDFF).withValues(alpha: 0.55),
          const Color(0xFF7FC6F2).withValues(alpha: 0),
        ],
        stops: const [0.0, 0.82, 0.97, 1.0],
      ).createShader(earthRect);
    canvas.drawCircle(c, r, rimPaint);

    canvas.restore();

    // 9. 流星（盘前划过，复用 StarrySky 分段算法）
    _drawMeteors(canvas, w, h);
  }

  void _drawAntarctica(Canvas canvas) {
    const lat0 = -65.0;
    final yTop = c.dy - r * sin(lat0 * pi / 180);
    final dy = yTop - c.dy;
    final halfChord = sqrt(max(0.0, r * r - dy * dy));
    final rect = Rect.fromCircle(center: c, radius: r);
    final startAng = atan2(dy, halfChord);
    final sweep = pi - 2 * startAng;
    final path = Path()
      ..moveTo(c.dx - halfChord, yTop)
      ..lineTo(c.dx + halfChord, yTop)
      ..arcTo(rect, startAng, sweep, false)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFD8E2E6));
  }

  void _drawContinent(Canvas canvas, _Continent cont, Paint paint) {
    var anyVisible = false;
    for (final p in cont.pts) {
      if (_relLon(p.lon).abs() < 90) {
        anyVisible = true;
        break;
      }
    }
    if (!anyVisible) return;

    final path = Path();
    final pts = cont.pts;
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % n];
      final pa = _project(a.lon, a.lat);
      if (i == 0) {
        path.moveTo(pa.dx, pa.dy);
      } else {
        path.lineTo(pa.dx, pa.dy);
      }
      final sub = _subdiv(b.lon - a.lon);
      for (var s = 1; s <= sub; s++) {
        final f = s / (sub + 1);
        final sp = _project(
          a.lon + (b.lon - a.lon) * f,
          a.lat + (b.lat - a.lat) * f,
        );
        path.lineTo(sp.dx, sp.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawMeteors(Canvas canvas, double w, double h) {
    const dirX = -0.7, dirY = 0.71;
    const tailLen = 70.0;
    const segments = 10;
    final segPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      if (phase > 0.80) continue;
      final p = phase / 0.80;
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
  bool shouldRepaint(covariant _EarthPainter old) => old.t != t;
}
