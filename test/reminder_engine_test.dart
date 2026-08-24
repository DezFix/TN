import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/reminder_engine.dart';

void main() {
String fakeTr(String key, [List<String>? args]) =>
    key + (args == null ? '' : ':${args.join(",")}');

  Entry todoEntry(String id, int? dueAt, {String type = 'todo'}) => Entry(
        id: id,
        chatId: 'c1',
        type: type,
        ts: 0,
        items: [TodoItem(id: 'i1', text: 'task')],
        dueAt: dueAt,
      );

  group('collectDue', () {
    final now = 10 * 24 * 3600 * 1000; // some fixed "now"
    final hour = 3600 * 1000;

    test('includes reminder due right now', () {
      final due = collectDue(
        reminders: [Reminder(id: 'r1', chatId: 'c1', when: now)],
        entries: const [],
        chatNameOf: (_) => 'X',
        tr: fakeTr,
        now: now,
      );
      expect(due.single.key, 'r1|$now');
      expect(due.single.title, contains('remind_title'));
      expect(due.single.title, contains('X'));
    });

    test('excludes future and stale (older than 24h)', () {
      final due = collectDue(
        reminders: [
          Reminder(id: 'future', chatId: 'c1', when: now + hour),
          Reminder(id: 'ancient', chatId: 'c1', when: now - 25 * hour),
          Reminder(id: 'ok', chatId: 'c1', when: now - 23 * hour),
        ],
        entries: const [],
        chatNameOf: (_) => 'X',
        tr: fakeTr,
        now: now,
      );
      expect(due.map((d) => d.key), ['ok|${now - 23 * hour}']);
    });

    test('includes todo deadlines, skips other entry types', () {
      final due = collectDue(
        reminders: const [],
        entries: [
          todoEntry('t1', now),
          todoEntry('t2', null),
          Entry(id: 'x', chatId: 'c1', type: 'text', ts: 0, text: 'hi'),
        ],
        chatNameOf: (_) => 'X',
        tr: fakeTr,
        now: now,
      );
      expect(due.single.key, 't1|$now');
    });

    test('same id rescheduled to a new time fires again (distinct keys)', () {
      final a = collectDue(
          reminders: [Reminder(id: 'r', chatId: 'c1', when: now)],
          entries: const [],
          chatNameOf: (_) => 'X',
          tr: fakeTr,
          now: now);
      final b = collectDue(
          reminders: [Reminder(id: 'r', chatId: 'c1', when: now + hour)],
          entries: const [],
          chatNameOf: (_) => 'X',
          tr: fakeTr,
          now: now + hour);
      expect(a.single.key == b.single.key, isFalse);
    });

    test('same deadline via reminder AND todo entry delivers once', () {
      final due = collectDue(
        reminders: [Reminder(id: 't1', chatId: 'c1', when: now)],
        entries: [todoEntry('t1', now)],
        chatNameOf: (_) => 'X',
        tr: fakeTr,
        now: now,
      );
      expect(due.length, 1);
    });
  });
}
