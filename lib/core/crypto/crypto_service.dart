import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../constants.dart';

/// 加密服务 —— 核心层
///
/// - PBKDF2-HMAC-SHA256（≥120,000 次迭代）：用户密码哈希、主密钥派生
/// - AES-256-GCM：AI API Key 等敏感数据加密（密钥派生自主密码，仅存内存）
/// - SHA-256：.starhope 负载摘要防伪
///
/// 纯 Dart 实现（pointycastle + crypto），无平台原生依赖，全平台一致。
class CryptoService {
  CryptoService._();

  static final Random _secure = Random.secure();

  /// 生成随机盐（hex）
  static String generateSaltHex({int bytes = AppConstants.saltBytes}) =>
      _toHex(_randomBytes(bytes));

  /// 生成随机 ID
  static String generateId({int bytes = 12}) => _toHex(_randomBytes(bytes));

  static Uint8List _randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _secure.nextInt(256);
    }
    return b;
  }

  // ---------------- PBKDF2 ----------------

  /// PBKDF2 派生密钥（bytes）
  static Uint8List pbkdf2(
    String password,
    String saltHex, {
    int iterations = AppConstants.pbkdf2Iterations,
    int keyBits = AppConstants.pbkdf2KeyBits,
  }) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(
        _fromHex(saltHex), iterations, keyBits ~/ 8));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// PBKDF2 输出（hex）—— 用于密码哈希存储与校验
  static String pbkdf2Hex(
    String password,
    String saltHex, {
    int? iterations,
  }) {
    final it = iterations ?? AppConstants.pbkdf2Iterations;
    return _toHex(pbkdf2(password, saltHex, iterations: it));
  }

  /// 校验密码：常量时间比较
  static bool verifyPassword(
          String plain, String saltHex, String expectedHash) =>
      _constTimeEq(pbkdf2Hex(plain, saltHex), expectedHash);

  /// 校验已派生的密钥与期望哈希是否一致（常量时间比较）。
  /// 用于复用一次 PBKDF2 派生结果同时做密码校验与主密钥（避免重复计算）。
  static bool verifyDerivedHex(Uint8List derived, String expectedHash) =>
      _constTimeEq(_toHex(derived), expectedHash);

  // ---------------- AES-256-GCM ----------------

  /// 加密明文，返回 "iv(hex):ciphertext+tag(base64)"
  static String encryptString(String plaintext, Uint8List key) {
    final iv = _randomBytes(AppConstants.ivBytes);
    final ct = _gcm(true, key, iv, Uint8List.fromList(utf8.encode(plaintext)));
    return '${_toHex(iv)}:${base64.encode(ct)}';
  }

  /// 解密 "iv(hex):ciphertext+tag(base64)"，失败抛异常
  static String decryptString(String packed, Uint8List key) {
    final idx = packed.indexOf(':');
    if (idx <= 0) throw const FormatException('密文格式错误');
    final iv = _fromHex(packed.substring(0, idx));
    final ct = base64.decode(packed.substring(idx + 1));
    final plain = _gcm(false, key, iv, ct);
    return utf8.decode(plain);
  }

  static Uint8List _gcm(
      bool forEncryption, Uint8List key, Uint8List iv, Uint8List data) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(forEncryption, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    // pointycastle 的 process() 内部完成 processBytes + doFinal：
    // 加密返回 密文+tag；解密返回明文并校验 tag（失败抛 InvalidCipherTextException）
    return cipher.process(data);
  }

  // ---------------- SHA-256 ----------------

  static String sha256Hex(String data) =>
      sha256.convert(utf8.encode(data)).toString();

  static String sha256BytesHex(Uint8List data) =>
      sha256.convert(data).toString();

  // ---------------- helpers ----------------

  static String _toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _fromHex(String hex) {
    if (hex.length.isOdd) hex = '0$hex';
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static bool _constTimeEq(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }
}
