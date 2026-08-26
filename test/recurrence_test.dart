import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/models.dart';

void main() {
  int ms(int y, int m, int d, [int h = 9, int min = 0]) =>
      DateTime(y, m, d, h, min).millisecondsSinceEpoch;

  DateTime dt(int y, int m, int d, [int h = 9, int min = 0]) => DateTime(y, m, d, h, min);

  group('nextOccurrence', () {
    test('daily: next day, same time', () {
      final got = nextOccurrence(
          recurrence: 'daily', fromMs: ms(2026, 8, 24), after: dt(2026, 8, 24));
      expect(DateTime.fromMillisecondsSinceEpoch(got), dt(2026, 8, 25));
    });

    test('weekly: picks next selected weekday (Fri -> Wed)', () {
      // 2026-08-21 is Friday; Wednesday is 26th.
      final got = nextOccurrence(
          recurrence: 'weekly',
          days: const [3],
          fromMs: ms(2026, 8, 21),
          after: dt(2026, 8, 21));
      expect(DateTime.fromMillisecondsSinceEpoch(got), dt(2026, 8, 26));
    });

    test('weekdays preset: Fri -> Mon', () {
      final got = nextOccurrence(
          recurrence: 'weekly',
          days: const [1, 2, 3, 4, 5],
          fromMs: ms(2026, 8, 21),
          after: dt(2026, 8, 21));
      expect(DateTime.fromMillisecondsSinceEpoch(got), dt(2026, 8, 24));
    });

    test('monthly day 31 clamped to Feb 28, keeps time', () {
      final got = nextOccurrence(
          recurrence: 'monthly',
          monthDay: 31,
          fromMs: ms(2026, 1, 31, 10, 30),
          after: dt(2026, 1, 31, 10, 30));
      expect(DateTime.fromMillisecondsSinceEpoch(got), dt(2026, 2, 28, 10, 30));
    });

    test('monthly day 15: 20 Jun -> 15 Jul', () {
      final got = nextOccurrence(
          recurrence: 'monthly',
          monthDay: 15,
          fromMs: ms(2026, 6, 20),
          after: dt(2026, 6, 20));
      expect(DateTime.fromMillisecondsSinceEpoch(got), dt(2026, 7, 15));
    });
  });

  group('rolloverRecurringTasks', () {
    Entry task({String? rec, List<int>? days, int? monthDay, required int dueAt, bool done = false}) =>
        Entry(
          id: 'e1',
          chatId: 'c1',
          type: 'todo',
          ts: 0,
          items: [
            TodoItem(id: 't1', text: 'дело', done: done),
            TodoItem(id: 't2', text: 'второе', done: done),
          ],
          dueAt: dueAt,
          recurrence: rec,
          recurrenceDays: days,
          monthDay: monthDay,
        );

    test('done daily task stays checked until next occurrence passes', () {
      final e = task(rec: 'daily', dueAt: ms(2026, 8, 24), done: true);
      // Same morning: period not over yet.
      expect(rolloverRecurringTasks([e], dt(2026, 8, 24, 12)), isEmpty);
      expect(e.items!.every((i) => i.done), isTrue);
      // Next day 09:00 has arrived: reset + jump.
      final rolled = rolloverRecurringTasks([e], dt(2026, 8, 25, 9, 1));
      expect(rolled, [e]);
      expect(e.items!.every((i) => i.done), isFalse);
      expect(DateTime.fromMillisecondsSinceEpoch(e.dueAt!), dt(2026, 8, 26));
    });

    test('catches up over several missed periods', () {
      final e = task(rec: 'daily', dueAt: ms(2026, 8, 24), done: true);
      rolloverRecurringTasks([e], dt(2026, 8, 30, 12)); // a week later
      expect(DateTime.fromMillisecondsSinceEpoch(e.dueAt!), dt(2026, 8, 31));
    });

    test('undone tasks are never touched', () {
      final e = task(rec: 'daily', dueAt: ms(2026, 8, 24), done: false);
      expect(rolloverRecurringTasks([e], dt(2026, 9, 30)), isEmpty);
      expect(e.items!.every((i) => i.done), isFalse);
      expect(e.dueAt, ms(2026, 8, 24));
    });

    test('non-recurring done tasks are never touched', () {
      final e = task(dueAt: ms(2026, 8, 24), done: true);
      expect(rolloverRecurringTasks([e], dt(2026, 9, 30)), isEmpty);
      expect(e.items!.every((i) => i.done), isTrue);
    });

    test('weekly stays checked all week, resets on next selected weekday', () {
      final e = task(rec: 'weekly', days: const [1], dueAt: ms(2026, 8, 24), done: true); // Mon
      // Thursday of the same week: period not over yet.
      expect(rolloverRecurringTasks([e], dt(2026, 8, 27, 10)), isEmpty);
      expect(e.items!.every((i) => i.done), isTrue);
      // Next Monday 09:01: reset + jump to following Monday.
      final rolled = rolloverRecurringTasks([e], dt(2026, 8, 31, 9, 1));
      expect(rolled, [e]);
      expect(e.items!.every((i) => i.done), isFalse);
      expect(DateTime.fromMillisecondsSinceEpoch(e.dueAt!), dt(2026, 9, 7));
    });

    test('monthly with monthDay clamping survives rollover', () {
      final e = task(rec: 'monthly', monthDay: 31, dueAt: ms(2026, 1, 31), done: true);
      rolloverRecurringTasks([e], dt(2026, 3, 5));
      expect(DateTime.fromMillisecondsSinceEpoch(e.dueAt!).day, 31);
      expect(e.items!.every((i) => i.done), isFalse);
    });
  });

  group('snapCompletedRecurring', () {
    Entry task({String? rec, List<int>? days, int? monthDay, required int dueAt, bool done = false}) =>
        Entry(
          id: 'e1',
          chatId: 'c1',
          type: 'todo',
          ts: 0,
          items: [
            TodoItem(id: 't1', text: 'дело', done: done),
            TodoItem(id: 't2', text: 'второе', done: done),
          ],
          dueAt: dueAt,
          recurrence: rec,
          recurrenceDays: days,
          monthDay: monthDay,
        );

    test('overdue daily completed today snaps to TODAY (midnight handover)', () {
      final e = task(rec: 'daily', dueAt: ms(2026, 8, 20), done: true);
      final snapped = snapCompletedRecurring(e, dt(2026, 8, 24, 12));
      expect(snapped, isTrue);
      // Calendar-day semantics: deadline becomes today's date with the
      // original clock time — tonight's 00:00 rollover then hands the
      // fresh instance to tomorrow; no day is skipped.
      expect(DateTime.fromMillisecondsSinceEpoch(e.dueAt!), dt(2026, 8, 24));
      expect(e.items!.every((i) => i.done), isTrue);
    });

    test('weekly overdue snaps to next selected weekday', () {
      final e = task(rec: 'weekly', days: const [3], dueAt: ms(2026, 8, 19), done: true); // Wed
      final snapped = snapCompletedRecurring(e, dt(2026, 8, 24, 12)); // Mon
      expect(snapped, isTrue);
      expect(DateTime.fromMillisecondsSinceEpoch(e.dueAt!), dt(2026, 8, 26)); // Wed
    });

    test('not-overdue completed task is untouched', () {
      final e = task(rec: 'daily', dueAt: ms(2026, 8, 25), done: true);
      expect(snapCompletedRecurring(e, dt(2026, 8, 24, 12)), isFalse);
      expect(e.dueAt, ms(2026, 8, 25));
    });

    test('partly-done overdue task is untouched', () {
      final e = Entry(
        id: 'e1',
        chatId: 'c1',
        type: 'todo',
        ts: 0,
        items: [
          TodoItem(id: 't1', text: 'дело', done: true),
          TodoItem(id: 't2', text: 'второе', done: false),
        ],
        dueAt: ms(2026, 8, 20),
        recurrence: 'daily',
      );
      expect(snapCompletedRecurring(e, dt(2026, 8, 24, 12)), isFalse);
      expect(e.dueAt, ms(2026, 8, 20));
    });

    test('non-recurring overdue completed task is untouched', () {
      final e = task(dueAt: ms(2026, 8, 20), done: true);
      expect(snapCompletedRecurring(e, dt(2026, 8, 24, 12)), isFalse);
      expect(e.dueAt, ms(2026, 8, 20));
    });

    test('monthly snap keeps clamped month day', () {
      final e = task(rec: 'monthly', monthDay: 31, dueAt: ms(2026, 1, 31), done: true);
      final snapped = snapCompletedRecurring(e, dt(2026, 2, 5));
      expect(snapped, isTrue);
      final d = DateTime.fromMillisecondsSinceEpoch(e.dueAt!);
      expect(d.month, 2);
      expect(d.day, 28); // clamped: no Feb 31
    });
  });
}
