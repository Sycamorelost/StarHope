import 'package:flutter/material.dart';

import '../../services/window_service.dart';

/// 自定义无边框窗口标题栏：可拖动 + 最小化/最大化/关闭按钮。
///
/// 圆角与窗口区域融合，高度 36，半透明毛玻璃。
class WindowTitleBar extends StatelessWidget {
  final String title;
  final bool showMaximize;
  final List<Widget>? leading;
  final Color? foreground;

  const WindowTitleBar({
    super.key,
    this.title = 'StarHope',
    this.showMaximize = true,
    this.leading,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = foreground ?? cs.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowService.startDrag(),
      onDoubleTap: showMaximize ? () => WindowService.toggleMaximize() : null,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (leading != null) ...leading!, const SizedBox(width: 4),
            Icon(Icons.auto_awesome, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg.withValues(alpha: 0.85))),
            const Spacer(),
            _ctrlButton(context, Icons.fullscreen, '全屏 (F11)',
                () => WindowService.toggleFullscreen()),
            const SizedBox(width: 2),
            _ctrlButton(context, Icons.remove, '最小化',
                () => WindowService.minimize()),
            if (showMaximize)
              _ctrlButton(context, Icons.crop_square, '最大化',
                  () => WindowService.toggleMaximize()),
            _ctrlButton(context, Icons.close, '关闭', () => WindowService.close(),
                isClose: true),
          ],
        ),
      ),
    );
  }

  Widget _ctrlButton(BuildContext context, IconData icon, String tooltip,
      VoidCallback onTap,
      {bool isClose = false}) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: isClose ? Colors.transparent : Colors.transparent,
          ),
          child: Icon(icon, size: 15,
              color: isClose ? cs.error : cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
