import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for backups: AES-256-GCM with a PBKDF2-HMAC-SHA256
/// key stretched from the user's password. Layout of an encrypted backup:
///
///   `TNENC1` | salt(16) | nonce(12) | ciphertext… | gcm-tag(16)
///
/// The magic prefix lets [isEncrypted] detect the format instantly (plain
/// zip starts with `PK`), so restore flows can ask for a password only when
/// it is actually needed.
class BackupCrypto {
  BackupCrypto._();

  static const magic = 'TNENC1';
  static const saltLen = 16;
  static const nonceLen = 12;
  static const tagLen = 16;

  /// 120k PBKDF2 rounds — fast on accelerated platforms, tolerable (~seconds)
  /// on the pure-Dart fallback.
  static const iterations = 120000;

  static final _aes = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );

  static bool isEncrypted(List<int> bytes) {
    if (bytes.length < magic.length + saltLen + nonceLen + tagLen) return false;
    final head = utf8.decode(bytes.sublist(0, magic.length), allowMalformed: true);
    return head == magic;
  }

  /// Throws ArgumentError when [password] is empty — silent unencrypted
  /// uploads are exactly what this feature prevents.
  static Future<List<int>> encrypt(List<int> plain, String password) async {
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', 'must not be empty');
    }
    final salt = _random(saltLen);
    final nonce = _random(nonceLen);
    final key = await _deriveKey(password, salt);
    final box = await _aes.encrypt(
      Uint8List.fromList(plain),
      secretKey: key,
      nonce: nonce,
    );
    final out = BytesBuilder()
      ..add(utf8.encode(magic))
      ..add(salt)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  /// Returns the decrypted bytes, or null when the password is wrong / the
  /// container is corrupted (GCM authentication failure).
  static Future<List<int>?> decrypt(List<int> data, String password) async {
    if (!isEncrypted(data) || password.isEmpty) return null;
    try {
      var i = magic.length;
      final salt = data.sublist(i, i + saltLen);
      i += saltLen;
      final nonce = data.sublist(i, i + nonceLen);
      final cipherStart = i + nonceLen;
      final cipher =
          data.sublist(cipherStart, data.length - tagLen);
      final mac = data.sublist(data.length - tagLen);
      final key = await _deriveKey(password, salt);
      return await _aes.decrypt(
        SecretBox(
          cipher,
          nonce: nonce,
          mac: Mac(mac),
        ),
        secretKey: key,
      );
    } catch (_) {
      // Wrong password or damaged file — GCM tag check failed.
      return null;
    }
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      _kdf.deriveKeyFromPassword(password: password, nonce: salt);

  static List<int> _random(int n) {
    final rnd = Random.secure();
    return List.generate(n, (_) => rnd.nextInt(256));
  }
}
