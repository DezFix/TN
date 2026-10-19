import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/app_lock.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLock.kdfIterations = 2000;
    AppLock.nowFn = DateTime.now;
  });

  group('AppLock secret hashing (pattern / PIN)', () {
    test('hash+verify roundtrip', () async {
      final stored = AppLock.hashSecret('1-4-8', 'deadbeef00112233');
      expect(AppLock.verifyAgainst('1-4-8', stored), isTrue);
      expect(AppLock.verifyAgainst('0-4-8', stored), isFalse);
      expect(AppLock.verifyAgainst('', stored), isFalse);
    });

    test('same code, different salts → different hashes', () {
      final a = AppLock.hashSecret('1234', 'aaaa');
      final b = AppLock.hashSecret('1234', 'bbbb');
      expect(a != b, isTrue);
    });

    test('malformed stored value never verifies', () {
      expect(AppLock.verifyAgainst('1234', 'no-separator'), isFalse);
      expect(AppLock.verifyAgainst('1234', ''), isFalse);
    });

    test('grace window math', () async {
      AppLock.nowFn = () => DateTime(2026, 1, 1, 12, 0);
      // No unlock yet.
      expect(await AppLock.isWithinGrace(), isFalse);
      AppLock.markUnlocked();
      // grace=0 means immediate re-lock.
      expect(await AppLock.isWithinGrace(), isFalse);
    });
  });

  group('AppLock KDF hashing', () {
    test('stored format is KDF and roundtrips', () {
      final stored = AppLock.hashSecret('1234', 'deadbeef');
      expect(stored.startsWith('kdf1:'), isTrue);
      expect(AppLock.verifyAgainst('1234', stored), isTrue);
      expect(AppLock.verifyAgainst('4321', stored), isFalse);
    });

    test('legacy single-round hash still verifies', () {
      final legacy = AppLock.hashSecretLegacy('1234', 'abcd');
      expect(legacy.startsWith('kdf1:'), isFalse);
      expect(AppLock.verifyAgainst('1234', legacy), isTrue);
      expect(AppLock.verifyAgainst('0000', legacy), isFalse);
    });

    test('malformed KDF values never verify', () {
      expect(AppLock.verifyAgainst('1234', 'kdf1:x:abcd:aa'), isFalse);
      expect(AppLock.verifyAgainst('1234', 'kdf1:0:abcd:aa'), isFalse);
      expect(AppLock.verifyAgainst('1234', 'kdf1:99999999:abcd:aa'), isFalse);
      expect(AppLock.verifyAgainst('1234', 'kdf1:2000:abcd'), isFalse);
    });

    test('verifyCode upgrades a legacy secret to KDF in place', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'tn-lock-secret-pin',
        AppLock.hashSecretLegacy('1234', 'abcd'),
      );
      expect(await AppLock.verifyCode('1234', LockMethod.pin), isTrue);
      expect(
        prefs.getString('tn-lock-secret-pin')!.startsWith('kdf1:'),
        isTrue,
      );
      expect(await AppLock.verifyCode('1234', LockMethod.pin), isTrue);
    });
  });

  group('AppLock brute-force limiting', () {
    test('delays start after free tries and double', () async {
      AppLock.nowFn = () => DateTime(2026, 1, 1, 12, 0);
      for (var i = 1; i < AppLock.lockoutFreeTries; i++) {
        expect(await AppLock.registerFailedAttempt(), 0);
      }
      expect(await AppLock.registerFailedAttempt(), 30);
      expect(await AppLock.lockoutSecondsLeft(), 30);
      expect(await AppLock.registerFailedAttempt(), 60);
      expect(await AppLock.lockoutSecondsLeft(), 60);
      expect(await AppLock.failedAttempts(), AppLock.lockoutFreeTries + 1);
    });

    test('lockout expires with time', () async {
      var now = DateTime(2026, 1, 1, 12, 0);
      AppLock.nowFn = () => now;
      for (var i = 0; i < AppLock.lockoutFreeTries; i++) {
        await AppLock.registerFailedAttempt();
      }
      expect(await AppLock.lockoutSecondsLeft(), 30);
      now = now.add(const Duration(seconds: 30));
      expect(await AppLock.lockoutSecondsLeft(), 0);
    });

    test('delay is capped at 32 minutes', () async {
      AppLock.nowFn = () => DateTime(2026, 1, 1, 12, 0);
      var last = 0;
      for (var i = 0; i < 40; i++) {
        last = await AppLock.registerFailedAttempt();
      }
      expect(last, 1920);
    });

    test('reset clears count and lockout', () async {
      AppLock.nowFn = () => DateTime(2026, 1, 1, 12, 0);
      for (var i = 0; i < AppLock.lockoutFreeTries; i++) {
        await AppLock.registerFailedAttempt();
      }
      expect(await AppLock.lockoutSecondsLeft(), greaterThan(0));
      await AppLock.resetFailedAttempts();
      expect(await AppLock.failedAttempts(), 0);
      expect(await AppLock.lockoutSecondsLeft(), 0);
    });
  });

  group('AppLock multi-method API', () {
    test('getEnabledMethods defaults to biometric', () async {
      final methods = await AppLock.getEnabledMethods();
      expect(methods, contains(LockMethod.biometric));
      expect(methods.length, 1);
    });

    test('setEnabledMethods persists and reads back', () async {
      await AppLock.setEnabledMethods({LockMethod.pattern, LockMethod.pin});
      final methods = await AppLock.getEnabledMethods();
      expect(methods, contains(LockMethod.pattern));
      expect(methods, contains(LockMethod.pin));
      expect(methods.length, 2);
    });

    test('isMethodEnabled returns correct value', () async {
      await AppLock.setEnabledMethods({LockMethod.pattern});
      expect(await AppLock.isMethodEnabled(LockMethod.pattern), isTrue);
      expect(await AppLock.isMethodEnabled(LockMethod.pin), isFalse);
      expect(await AppLock.isMethodEnabled(LockMethod.biometric), isFalse);
    });

    test('backward compat: reads legacy single-method key', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tn-lock-mode', 'pin');
      final methods = await AppLock.getEnabledMethods();
      expect(methods, contains(LockMethod.pin));
      expect(methods.length, 1);
    });

    test('setEnabledMethods writes legacy key for first method', () async {
      await AppLock.setEnabledMethods(
          {LockMethod.biometric, LockMethod.pattern});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tn-lock-mode'), isNotNull);
    });

    test('setEnabledMethods rejects empty set', () async {
      await AppLock.setEnabledMethods({LockMethod.pin});
      await AppLock.setEnabledMethods({});
      final methods = await AppLock.getEnabledMethods();
      expect(methods, contains(LockMethod.pin));
    });
  });
}
