import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储服务（服务层）
///
/// 仅用于"记住密码"功能：存储账号 + 加密的登录票据。
/// 桌面端经 Windows DPAPI 保护，移动端经 KeyStore/Keychain。
class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kAccount = 'remember_account';
  static const _kTicket = 'remember_ticket';
  static const _kTheme = 'theme_mode';
  static const _kEnterToSend = 'enter_to_send';
  static const _kLockHotkey = 'lock_hotkey';

  Future<void> saveRemember(String account, String ticket) async {
    await _storage.write(key: _kAccount, value: account);
    await _storage.write(key: _kTicket, value: ticket);
  }

  Future<String?> readRememberedAccount() => _storage.read(key: _kAccount);

  Future<String?> readRememberedTicket() => _storage.read(key: _kTicket);

  Future<void> clearRemember() async {
    await _storage.delete(key: _kAccount);
    await _storage.delete(key: _kTicket);
  }

  Future<void> setThemeMode(String mode) =>
      _storage.write(key: _kTheme, value: mode);

  Future<String?> getThemeMode() => _storage.read(key: _kTheme);

  // 回车键发送/确认偏好（默认开启）
  Future<void> setEnterToSend(bool v) =>
      _storage.write(key: _kEnterToSend, value: v.toString());

  Future<bool> getEnterToSend() async =>
      (await _storage.read(key: _kEnterToSend)) != 'false';

  // 锁定热键偏好（编码 'ctrl.m'：修饰键.键，默认 Ctrl+M）
  Future<void> setLockHotkey(String v) =>
      _storage.write(key: _kLockHotkey, value: v);

  Future<String?> getLockHotkey() => _storage.read(key: _kLockHotkey);

  /// 清空全部偏好（一键清空/恢复出厂用）
  Future<void> clearAll() => _storage.deleteAll();
}
