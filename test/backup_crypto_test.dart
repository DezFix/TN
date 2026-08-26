import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/backup.dart';
import 'package:tn/src/backup_crypto.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypt/decrypt roundtrip preserves bytes', () async {
    final plain = utf8.encode('{"chats":[],"entries":["привет"]}');
    final enc = await BackupCrypto.encrypt(plain, 'пароль123');
    expect(identical(enc, plain), isFalse);
    expect(BackupCrypto.isEncrypted(enc), isTrue);
    expect(BackupCrypto.isEncrypted(plain), isFalse);

    final dec = await BackupCrypto.decrypt(enc, 'пароль123');
    expect(dec, isNotNull);
    expect(utf8.decode(dec!), utf8.decode(plain));
  });

  test('wrong password returns null (GCM auth fails)', () async {
    final enc = await BackupCrypto.encrypt(utf8.encode('secret'), 'right');
    expect(await BackupCrypto.decrypt(enc, 'wrong'), isNull);
    expect(await BackupCrypto.decrypt(enc, ''), isNull);
  });

  test('ciphertext differs between runs (random salt/nonce)', () async {
    final a = await BackupCrypto.encrypt(utf8.encode('x'), 'p');
    final b = await BackupCrypto.encrypt(utf8.encode('x'), 'p');
    expect(Uint8List.fromList(a), isNot(Uint8List.fromList(b)));
  });

  test('empty password is rejected on encrypt', () async {
    expect(() => BackupCrypto.encrypt(utf8.encode('x'), ''),
        throwsArgumentError);
  });

  test('importFromBytes demands a password for encrypted backups', () async {
    SharedPreferences.setMockInitialValues({});
    // SharedPreferences mock for state.save() inside import path.
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'n', color: '#FFFFFF'));
    final rawZip = await BackupService.buildZip(state);
    final encZip = await BackupCrypto.encrypt(rawZip, 'pw');

    // Without password → BackupEncryptedException.
    expect(
      () => BackupService.importFromBytes(encZip, 'b.zip', AppState()),
      throwsA(isA<BackupEncryptedException>()),
    );

    // Wrong password → wrongPassword flag.
    try {
      await BackupService.importFromBytes(
          encZip, 'b.zip', AppState(), password: 'nope');
      fail('expected BackupEncryptedException');
    } on BackupEncryptedException catch (e) {
      expect(e.wrongPassword, isTrue);
    }

    // Right password → restores chats.
    final restored = AppState();
    await BackupService.importFromBytes(encZip, 'b.zip', restored,
        password: 'pw');
    expect(restored.chats.single.id, 'c1');

    // Plain (legacy) backups still import without a password.
    final legacy = AppState();
    await BackupService.importFromBytes(rawZip, 'b.zip', legacy);
    expect(legacy.chats.single.id, 'c1');
  });
}
