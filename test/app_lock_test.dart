import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/app_lock.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
