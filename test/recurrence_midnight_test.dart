import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/models.dart';

void main() {
  DateTime at(int y, int m, int d, int h, int min) => DateTime(y, m, d, h, min);
  int ms(DateTime dt) => dt.millisecondsSinceEpoch;

  Entry dailyEntry({required int dueAt, required List<TodoItem> items}) =>
      Entry(
        id: 'e1',
        chatId: 'c1',
        type: 'todo',
        ts: 0,
        dueAt: dueAt,
        recurrence: 'daily',
        items: items,
      );

  group('rolloverRecurringTasks — midnight semantics for daily', () {
    test('done yesterday 18:00 → resets at next morning, due TODAY 18:00',
        () {
      final now = at(2026, 8, 26, 9, 0); // this morning
      final e = dailyEntry(
        dueAt: ms(at(2026, 8, 25, 18, 0)), // yesterday evening, done
        items: [TodoItem(id: 't', text: 'task', done: true)],
      );

      final rolled = rolloverRecurringTasks([e], now);

      expect(rolled, [e]);
      expect(e.items!.single.done, isFalse,
          reason: 'the reset must happen at 00:00, not at the 18:00 deadline');
      expect(e.dueAt, ms(at(2026, 8, 26, 18, 0)),
          reason: 'fresh instance is TODAY at the same clock time');
    });

    test('same-day done task is NOT reset until tomorrow', () {
      final now = at(2026, 8, 26, 20, 0); // same day, after the 18:00 due
      final e = dailyEntry(
        dueAt: ms(at(2026, 8, 26, 18, 0)), // today, done at 19:00
        items: [TodoItem(id: 't', text: 'task', done: true)],
      );
      expect(rolloverRecurringTasks([e], now), isEmpty,
          reason: "today's period is still active — checked state holds");
    });
  });

  group('snapCompletedRecurring — completing an overdue daily task', () {
    test('completed TODAY (leftover from yesterday) snaps to TODAY, not '
        'tomorrow', () {
      final now = at(2026, 8, 26, 20, 0); // user ticks it in the evening
      final e = dailyEntry(
        dueAt: ms(at(2026, 8, 25, 18, 0)), // overdue since yesterday
        items: [TodoItem(id: 't', text: 'task', done: true)],
      );

      final changed = snapCompletedRecurring(e, now);

      expect(changed, isTrue);
      expect(e.dueAt, ms(at(2026, 8, 26, 18, 0)),
          reason:
              "deadline becomes TODAY's clock time so tonight's 00:00 "
              'rollover hands over to tomorrow — never skipping a day');
    });

    test('weekly overdue completion still jumps past now (unchanged)', () {
      // Wed Aug 26 2026 is a Wednesday; weekly on Mondays.
      final now = at(2026, 8, 26, 12, 0);
      final e = Entry(
        id: 'e2',
        chatId: 'c1',
        type: 'todo',
        ts: 0,
        dueAt: ms(at(2026, 8, 24, 9, 0)), // Monday, overdue
        recurrence: 'weekly',
        recurrenceDays: [1],
        items: [TodoItem(id: 't', text: 'x', done: true)],
      );

      snapCompletedRecurring(e, now);

      expect(e.dueAt, ms(at(2026, 8, 31, 9, 0)), reason: 'next Monday 09:00');
    });
  });
}
