import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('snoozeByKey shifts a custom reminder into the future', () async {
    final model = AppModel();
    final now = DateTime.now().millisecondsSinceEpoch;
    model.state.reminders.add(Reminder(id: 'r1', chatId: 'c1', when: now));

    final ok = await model.snoozeByKey('r1|$now', 10);
    expect(ok, isTrue);
    expect(model.state.reminders.single.when,
        greaterThan(now + 9 * 60 * 1000));
    expect(model.state.reminders.single.id, 'r1');
  });

  test('snoozeByKey shifts a todo deadline and bumps updatedAt', () async {
    final model = AppModel();
    final now = DateTime.now().millisecondsSinceEpoch;
    final e = Entry(
        id: 't1',
        chatId: 'c1',
        type: 'todo',
        ts: 1,
        items: [TodoItem(id: 'i', text: 'task')],
        dueAt: now);
    model.state.entries.add(e);

    final ok = await model.snoozeByKey('t1|$now', 60);
    expect(ok, isTrue);
    expect(e.dueAt, greaterThan(now + 59 * 60 * 1000));
    expect(e.updatedAt, greaterThanOrEqualTo(e.ts));
  });

  test('snoozing a recurring task keeps its clock time', () async {
    final model = AppModel();
    final now = DateTime.now().millisecondsSinceEpoch;
    final e = Entry(
        id: 't2',
        chatId: 'c1',
        type: 'todo',
        ts: 1,
        items: [TodoItem(id: 'i', text: 'task')],
        dueAt: now,
        recurrence: 'daily');
    model.state.entries.add(e);

    final ok = await model.snoozeByKey('t2|$now', 15);
    expect(ok, isTrue);
    expect(e.dueAt, now, reason: 'dueAt drives every future occurrence');
    final r = model.state.reminders.single;
    expect(r.id, 't2');
    expect(r.when, greaterThan(now + 14 * 60 * 1000));
    // A second postpone from the reminder's own notification moves it again.
    expect(await model.snoozeByKey('t2|${r.when}', 10), isTrue);
    expect(model.state.reminders.length, 1);
  });

  test('snoozeByKey with unknown key returns false', () async {
    final model = AppModel();
    expect(await model.snoozeByKey('ghost|123', 10), isFalse);
    expect(await model.snoozeByKey('garbage', 10), isFalse);
  });
}
