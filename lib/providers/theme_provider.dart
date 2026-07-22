import 'package:flutter/material.dart';

import '../services/secure_storage_service.dart';

/// 主题模式 Provider：system / light / dark
class ThemeProvider extends ChangeNotifier {
  final SecureStorageService _secure = SecureStorageService();
  ThemeMode _mode = ThemeMode.system;
  bool _enterToSend = true;
  String _lockHotkey = 'ctrl.m';

  ThemeMode get mode => _mode;
  /// 回车键发送（AI 对话）/ 确认（登录）偏好
  bool get enterToSend => _enterToSend;
  /// 锁定热键编码（'ctrl.m' 形式：修饰键.键）
  String get lockHotkey => _lockHotkey;

  Future<void> init() async {
    final saved = await _secure.getThemeMode();
    _mode = _parse(saved) ?? ThemeMode.system;
    _enterToSend = await _secure.getEnterToSend();
    _lockHotkey = (await _secure.getLockHotkey()) ?? 'ctrl.m';
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
}
