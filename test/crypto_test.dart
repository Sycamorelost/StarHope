import 'package:flutter_test/flutter_test.dart';
import 'package:starhope/core/crypto/crypto_service.dart';

void main() {
  group('CryptoService', () {
    test('PBKDF2 产出稳定且可复现', () {
      const salt = '00112233445566778899aabbccddeeff';
      final h1 = CryptoService.pbkdf2Hex('password123', salt);
      final h2 = CryptoService.pbkdf2Hex('password123', salt);
      expect(h1, h2);
      expect(h1.length, 64); // 256-bit = 64 hex chars
      expect(h1, isNot(equals(CryptoService.pbkdf2Hex('password124', salt))));
    });

    test('verifyPassword 正确校验', () {
      const salt = 'aabbccddeeff00112233445566778899';
      final hash = CryptoService.pbkdf2Hex('secret', salt);
      expect(CryptoService.verifyPassword('secret', salt, hash), isTrue);
      expect(CryptoService.verifyPassword('wrong', salt, hash), isFalse);
    });

    test('AES-256-GCM 加解密往返一致', () {
      const salt = '00112233445566778899aabbccddeeff';
      final key = CryptoService.pbkdf2('master', salt, iterations: 1000);
      const plain = 'StarHope AI API Key: sk-test-1234567890abcdef';
      final enc = CryptoService.encryptString(plain, key);
      expect(enc.contains(':'), isTrue);
      final dec = CryptoService.decryptString(enc, key);
      expect(dec, plain);
    });

    test('AES-GCM 密文随机（IV 每次不同）', () {
      const salt = '00112233445566778899aabbccddeeff';
      final key = CryptoService.pbkdf2('master', salt, iterations: 1000);
      final e1 = CryptoService.encryptString('same', key);
      final e2 = CryptoService.encryptString('same', key);
      expect(e1, isNot(equals(e2)));
    });

    test('AES-GCM 错误密钥应抛异常（认证失败）', () {
      const salt = '00112233445566778899aabbccddeeff';
      final key1 = CryptoService.pbkdf2('master1', salt, iterations: 1000);
      final key2 = CryptoService.pbkdf2('master2', salt, iterations: 1000);
      final enc = CryptoService.encryptString('secret', key1);
      expect(() => CryptoService.decryptString(enc, key2), throwsException);
    });

    test('SHA-256 摘要正确', () {
      expect(CryptoService.sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });
}
