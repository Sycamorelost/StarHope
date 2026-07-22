import 'package:flutter/material.dart';

import '../services/secure_storage_service.dart';

/// 关闭窗口时的行为
enum CloseAction { ask, minimize, exit }

/// 主题模式 Provider：system / light / dark
class ThemeProvider extends ChangeNotifier {
  final SecureStorageService _secure = SecureStorageService();
  ThemeMode _mode = ThemeMode.system;
  bool _enterToSend = true;
  String _lockHotkey = 'ctrl.m';
  CloseAction _closeAction = CloseAction.ask;
  bool _lockOnHide = false;

  ThemeMode get mode => _mode;
  /// 回车键发送（AI 对话）/ 确认（登录）偏好
  bool get enterToSend => _enterToSend;
  /// 锁定热键编码（'ctrl.m' 形式：修饰键.键）
  String get lockHotkey => _lockHotkey;
  /// 关闭窗口行为（询问/最小化到托盘/退出）
  CloseAction get closeAction => _closeAction;
  /// 最小化到托盘时自动锁定账户
  bool get lockOnHide => _lockOnHide;

  Future<void> init() async {
    final saved = await _secure.getThemeMode();
    _mode = _parse(saved) ?? ThemeMode.system;
    _enterToSend = await _secure.getEnterToSend();
    _lockHotkey = (await _secure.getLockHotkey()) ?? 'ctrl.m';
    _closeAction = _parseCloseAction(await _secure.getCloseAction());
    _lockOnHide = await _secure.getLockOnHide();
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    await _secure.setThemeMode(m.name);
    notifyListeners();
  }

  Future<void> setEnterToSend(bool v) async {
    _enterToSend = v;
    await _secure.setEnterToSend(v);
    notifyListeners();
  }

  Future<void> setLockHotkey(String v) async {
    _lockHotkey = v;
    await _secure.setLockHotkey(v);
    notifyListeners();
  }

  Future<void> setCloseAction(CloseAction v) async {
    _closeAction = v;
    await _secure.setCloseAction(v.name);
    notifyListeners();
  }

  Future<void> setLockOnHide(bool v) async {
    _lockOnHide = v;
    await _secure.setLockOnHide(v);
    notifyListeners();
  }

  ThemeMode? _parse(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  CloseAction _parseCloseAction(String? s) {
    switch (s) {
      case 'minimize':
        return CloseAction.minimize;
      case 'exit':
        return CloseAction.exit;
      default:
        return CloseAction.ask;
    }
  }
}
