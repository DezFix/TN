import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/app_model.dart';

void main() {
  // tr stub: returns the key itself, so we assert on 'today'/'yesterday'.
  String tr(String k) => k;

  int at(int year, int month, int day) =>
      DateTime(year, month, day, 12).millisecondsSinceEpoch;

  test('fmtDay: today', () {
    final now = DateTime.now();
    expect(fmtDay(at(now.year, now.month, now.day), tr), 'today');
  });

  test('fmtDay: yesterday', () {
    final y = DateTime.now().subtract(const Duration(days: 1));
    expect(fmtDay(at(y.year, y.month, y.day), tr), 'yesterday');
  });

  test('fmtDay: older date shows day + single month word', () {
    // A fixed past date far from "today" in either direction of the year.
    final s = fmtDay(at(2024, 7, 21), tr);
    expect(s, '21 июля');
    expect(s.contains('['), isFalse,
        reason: 'interpolation bug would render the whole months list');
  });

  test('fmtDay: january index edge (month - 1 == 0)', () {
    final s = fmtDay(at(2023, 1, 5), tr);
    expect(s, '5 января');
  });

  test('fmtDay: december index edge (month - 1 == 11)', () {
    final s = fmtDay(at(2023, 12, 31), tr);
    expect(s, '31 декабря');
  });
}
