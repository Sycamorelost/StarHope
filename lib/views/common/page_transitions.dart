import 'package:flutter/material.dart';

/// 同级页面/内容渐变切换器（近似 Material fade-through）。
///
/// 基于 [AnimatedSwitcher]：子项切换时旧项淡出（~190ms）、新项淡入并轻微放大
/// （0.96→1.0，~380ms），比默认交叉淡入淡出更干净，减少两层叠化错位断层。
///
/// 用法：`FadeThroughSwitcher(switchKey: ValueKey(state), child: page)`，
/// `switchKey` 变化即触发渐变。适用于登录态切换、主页 tab 切换等同级场景。
class FadeThroughSwitcher<T> extends StatelessWidget {
  final Widget child;
  final ValueKey<T> switchKey;
  final Duration duration;

  const FadeThroughSwitcher({
    super.key,
    required this.child,
    required this.switchKey,
    this.duration = const Duration(milliseconds: 380),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration ~/ 2,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
          child: c,
        ),
      ),
      child: KeyedSubtree(key: switchKey, child: child),
    );
  }
}

/// push 详情页过渡：从右滑入 + 淡入。配置到 [MaterialApp.pageTransitionsTheme]
/// 后，所有 [MaterialPageRoute]（含现有与未来新增）自动继承，无需逐处改动。
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T extends Object?>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}
