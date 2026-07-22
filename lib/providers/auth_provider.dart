import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/models/user.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';

/// 认证状态 Provider
class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final SecureStorageService _secure = SecureStorageService();

  User? _user;
  bool _loading = true;
  String? _rememberedAccount;
  bool _hasUser = false;
  User? _registeredUser; // 已注册用户（登录前用于登录页展示头像/账号）

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;
  bool get hasUser => _hasUser;
  String? get rememberedAccount => _rememberedAccount;
  User? get registeredUser => _registeredUser;
  Uint8List? get masterKey => _auth.masterKey;

  Future<void> bootstrap() async {
    _hasUser = await _auth.hasUser();
    _registeredUser = await _auth.storedUser();
    _rememberedAccount = await _secure.readRememberedAccount();
    _loading = false;
    notifyListeners();
  }

  Future<User> register({
    required String account,
    required String password,
    required String nickname,
    String? avatarPath,
    String? github,
    String? qq,
    String? wechat,
  }) async {
    final u = await _auth.register(
      account: account,
      password: password,
      nickname: nickname,
      avatarPath: avatarPath,
      github: github,
      qq: qq,
      wechat: wechat,
    );
    _user = u;
    _hasUser = true;
    _registeredUser = u;
    notifyListeners();
    return u;
  }

  Future<User> login(String account, String password,
      {bool remember = false}) async {
    final u = await _auth.login(account, password);
    _user = u;
    if (remember) {
      // 仅存账号 + 一个登录票据（密码哈希前缀，用于校验），不存明文密码
      await _secure.saveRemember(account, '${u.salt.substring(0, 8)}:${u.passwordHash.substring(0, 16)}');
    } else {
      await _secure.clearRemember();
    }
    notifyListeners();
    return u;
  }

  Future<bool> verifyMaster(String password) =>
      _auth.verifyMasterPassword(password);

  Future<User> updateProfile({
    String? nickname,
    String? avatarPath,
    String? github,
    String? qq,
    String? wechat,
    String? newPassword,
    String? oldPassword,
  }) async {
    final u = await _auth.updateProfile(
      nickname: nickname,
      avatarPath: avatarPath,
      github: github,
      qq: qq,
      wechat: wechat,
      newPassword: newPassword,
      oldPasswordForRekey: oldPassword,
    );
    _user = u;
    _registeredUser = u;
    notifyListeners();
    return u;
  }

  void logout() {
    _auth.logout();
    _user = null;
    notifyListeners();
  }
}
