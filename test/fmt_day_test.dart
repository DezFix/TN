import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/app_model.dart';

void main() {
  // tr stub: returns the key itself, so we assert on 'today'/'yesterday'
  // and on the month keys ('month_7' etc.).
  String tr(String k, [List<String>? args]) => k;

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

  test('fmtDay: older date uses localized month key', () {
    // Months come from i18n (month_1..12) — no more hardcoded Russian list.
    final s = fmtDay(at(2024, 7, 21), tr);
    expect(s, '21 month_7 2024');
    expect(s.contains('['), isFalse,
        reason: 'interpolation bug would render a raw list');
  });

  test('fmtDay: january key edge', () {
    expect(fmtDay(at(2023, 1, 5), tr), '5 month_1 2023');
  });

  test('fmtDay: december key edge', () {
    expect(fmtDay(at(2023, 12, 31), tr), '31 month_12 2023');
  });
}
