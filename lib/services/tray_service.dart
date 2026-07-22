import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'window_service.dart';

/// 系统托盘服务（单例）。
///
/// 启动时建立托盘图标 + 右键菜单（显示窗口 / 退出）；左键点击托盘恢复窗口。
/// 配合 [WindowService.hide]/[show] 实现"关闭窗口最小化到托盘"。
class TrayService with TrayListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  bool _initialized = false;
  void Function()? _onLock;

  Future<void> init({void Function()? onLock}) async {
    if (_initialized) return;
    _onLock = onLock;
    try {
      await TrayManager.instance.setIcon('assets/icon.ico');
      await TrayManager.instance.setToolTip('StarHope');
      await TrayManager.instance.setContextMenu(Menu(items: [
        MenuItem(
            key: 'show',
            label: '显示窗口',
            onClick: (_) => WindowService.show()),
        if (_onLock != null)
          MenuItem(
              key: 'lock',
              label: '锁定账号',
              onClick: (_) => _onLock!()),
        MenuItem.separator(),
        MenuItem(
            key: 'exit', label: '关闭应用', onClick: (_) => _exit()),
      ]));
      TrayManager.instance.addListener(this);
      _initialized = true;
    } catch (e) {
      debugPrint('TrayService init failed: $e');
    }
  }

  /// 左键按下托盘图标 → 恢复窗口。
  @override
  void onTrayIconMouseDown() => WindowService.show();

  /// 真正退出应用（销毁托盘 + 关闭窗口触发进程退出）。
  Future<void> _exit() async {
    await TrayManager.instance.destroy();
    WindowService.close();
  }
}
