import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../core/constants.dart';
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
            const SizedBox(width: 8),
            Text(AppConstants.poweredBy,
                style: TextStyle(fontSize: 9, color: fg.withValues(alpha: 0.4))),
            const Spacer(),
            const _TopmostButton(),
            _ctrlButton(context, Icons.fullscreen, '全屏 (F11)',
                () => WindowService.toggleFullscreen()),
            const SizedBox(width: 2),
            _ctrlButton(context, Icons.remove, '最小化',
                () => WindowService.minimize()),
            if (showMaximize)
              _ctrlButton(context, Icons.crop_square, '最大化',
                  () => WindowService.toggleMaximize()),
            _ctrlButton(context, Icons.close, '关闭',
                () => handleCloseAction(context),
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

/// 处理窗口关闭：按用户设置（询问/最小化到托盘/退出）+ 可选自动锁定。
Future<void> handleCloseAction(BuildContext context) async {
  if (WindowService.isExamLocked) return; // 考试中禁止关闭
  final theme = context.read<ThemeProvider>();
  CloseAction? action = theme.closeAction;
  if (action == CloseAction.ask) {
    action = await _showCloseDialog(context);
    if (action == null) return; // 用户取消
  }
  if (!context.mounted) return;
  if (action == CloseAction.minimize) {
    if (theme.lockOnHide) {
      context.read<AuthProvider>().logout();
    }
    WindowService.hide();
  } else {
    WindowService.close();
  }
}

/// 首次关闭询问对话框：最小化到托盘 / 退出应用（可勾选"记住选择"）。
Future<CloseAction?> _showCloseDialog(BuildContext context) {
  final theme = context.read<ThemeProvider>();
  var remember = true;
  return showDialog<CloseAction>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('关闭窗口'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('希望关闭窗口时：'),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: remember,
              onChanged: (v) => setState(() => remember = v ?? false),
              title: const Text('记住选择（可在设置中修改）'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (remember) theme.setCloseAction(CloseAction.exit);
              Navigator.pop(ctx, CloseAction.exit);
            },
            child: const Text('退出应用'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.vertical_align_bottom, size: 18),
            label: const Text('最小化到托盘'),
            onPressed: () {
              if (remember) theme.setCloseAction(CloseAction.minimize);
              Navigator.pop(ctx, CloseAction.minimize);
            },
          ),
        ],
      ),
    ),
  );
}

/// 窗口置顶按钮（钉子，放全屏按钮左侧）。
class _TopmostButton extends StatefulWidget {
  const _TopmostButton();
  @override
  State<_TopmostButton> createState() => _TopmostButtonState();
}

class _TopmostButtonState extends State<_TopmostButton> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topmost = WindowService.isTopmost;
    return Tooltip(
      message: topmost ? '取消置顶' : '置顶',
      child: InkWell(
        onTap: () {
          WindowService.toggleTopmost();
          setState(() {});
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 28,
          alignment: Alignment.center,
          child: Icon(Icons.push_pin,
              size: 15, color: topmost ? cs.primary : cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
