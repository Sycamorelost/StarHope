import 'dart:isolate';
import 'dart:typed_data';

import '../core/constants.dart';
import '../core/crypto/crypto_service.dart';
import '../core/models/user.dart';
import 'database/database.dart';

/// 认证服务（服务层）
///
/// - 注册：本地单账户，首次启动强制注册。密码 PBKDF2 加盐哈希存储。
/// - 登录：校验密码哈希。
/// - 主密码 -> AES-256 密钥派生（内存中，用于加密 AI API Key 等敏感数据）。
class AuthService {
  final AppDatabase _db = AppDatabase.instance;

  User? _currentUser;
  Uint8List? _masterKey; // 仅登录后存在于内存，退出即焚

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get hasMasterKey => _masterKey != null;
  Uint8List? get masterKey => _masterKey;

  Future<bool> hasUser() async => (await _db.loadUser()) != null;

  /// 读取已注册用户（用于登录页展示头像/账号；未注册返回 null）
  Future<User?> storedUser() => _db.loadUser();

  /// 注册（本地单账户，若已存在用户则失败）
  Future<User> register({
    required String account,
    required String password,
    required String nickname,
    String? avatarPath,
    String? github,
    String? qq,
    String? wechat,
  }) async {
    if (await _db.loadUser() != null) {
      throw StateError('已存在本地账户，不可重复注册');
    }
    if (account.trim().isEmpty) throw ArgumentError('账号不能为空');
    if (password.length < 6) throw ArgumentError('密码至少 6 位');
    if (nickname.trim().isEmpty) throw ArgumentError('昵称不能为空');

    final salt = CryptoService.generateSaltHex();
    final hash = CryptoService.pbkdf2Hex(password, salt);
    final now = DateTime.now().millisecondsSinceEpoch;
    final user = User(
      id: CryptoService.generateId(),
      account: account.trim(),
      nickname: nickname.trim(),
      passwordHash: hash,
      salt: salt,
      avatarPath: avatarPath,
      github: github?.trim(),
      qq: qq?.trim(),
      wechat: wechat?.trim(),
      createdAt: now,
    );
    await _db.saveUser(user);
    _currentUser = user;
    _masterKey = _deriveKey(password, salt);
    return user;
  }

  /// 登录
  Future<User> login(String account, String password) async {
    final user = await _db.loadUser();
    if (user == null) throw StateError('尚未注册');
    if (user.account != account.trim()) {
      throw ArgumentError('账号不匹配');
    }
    // PBKDF2（120000 次迭代）在后台 isolate 计算，避免阻塞 UI 主线程导致
    // 登录 loading 动画卡顿；一次派生同时用于密码校验与主密钥（原先
    // verifyPassword + _deriveKey 各算一次，主线程两次阻塞）。
    final salt = user.salt;
    final derived = await Isolate.run(
      () => CryptoService.pbkdf2(password, salt),
    );
    if (!CryptoService.verifyDerivedHex(derived, user.passwordHash)) {
      throw ArgumentError('密码错误');
    }
    _currentUser = user;
    _masterKey = derived;
    return user;
  }

  /// 主密码二次验证（敏感操作前调用）
  Future<bool> verifyMasterPassword(String password) async {
    final user = _currentUser ?? await _db.loadUser();
    if (user == null) return false;
    return CryptoService.verifyPassword(password, user.salt, user.passwordHash);
  }

  /// 更新资料（含可选改密）
  Future<User> updateProfile({
    String? nickname,
    String? avatarPath,
    String? github,
    String? qq,
    String? wechat,
    String? newPassword,
    String? oldPasswordForRekey,
  }) async {
    final user = _currentUser!;
    var updated = user.copyWith(
      nickname: nickname,
      avatarPath: avatarPath,
      github: github,
      qq: qq,
      wechat: wechat,
    );

    // 改密：需要旧密码验证，并重派生主密钥
    if (newPassword != null && newPassword.isNotEmpty) {
      if (oldPasswordForRekey == null ||
          !CryptoService.verifyPassword(
              oldPasswordForRekey, user.salt, user.passwordHash)) {
        throw ArgumentError('原密码错误');
      }
      final newSalt = CryptoService.generateSaltHex();
      final newHash = CryptoService.pbkdf2Hex(newPassword, newSalt);
      updated = updated.copyWith(passwordHash: newHash, salt: newSalt);
      _masterKey = _deriveKey(newPassword, newSalt);
      // 注意：改密后旧主密钥失效，已加密的 AI Key 需要重新加密
      // 由调用方在确认后处理（见 AIService.rekeyAll）
    }

    await _db.saveUser(updated);
    _currentUser = updated;
    return updated;
  }

  void logout() {
    _currentUser = null;
    _masterKey = null; // 用完即焚
  }

  Uint8List _deriveKey(String password, String saltHex) {
    return CryptoService.pbkdf2(password, saltHex,
        iterations: AppConstants.pbkdf2Iterations,
        keyBits: AppConstants.pbkdf2KeyBits);
  }
}
