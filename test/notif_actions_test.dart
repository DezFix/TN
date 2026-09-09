import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/reminders.dart';
import 'package:tn/src/state.dart';

NotificationResponse resp(String actionId, String payload) =>
    NotificationResponse(
      id: 1,
      actionId: actionId,
      payload: payload,
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
    );

Future<void> seed(AppState state) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(storageKey, state.toJson());
}

AppState loadState(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final state = AppState();
  state.loadFromJson(raw);
  expect(data, isNotNull);
  return state;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('notif done marks the todo entry done', () async {
    final state = AppState();
    state.entries.add(Entry(
      id: 'e1',
      chatId: 'c1',
      type: 'todo',
      ts: 0,
      items: [TodoItem(id: 'i', text: 'task')],
      dueAt: 1000,
    ));
    await seed(state);

    expect(await handleSnoozeResponse(resp(notifDoneAction, 'e1|1000')), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final back = loadState(prefs.getString(storageKey)!);
    expect(back.entries.single.items!.single.done, isTrue);
  });

  test('notif done drops a custom reminder', () async {
    final state = AppState();
    state.reminders.add(Reminder(id: 'r1', chatId: 'c1', when: 1000));
    await seed(state);

    expect(await handleSnoozeResponse(resp(notifDoneAction, 'r1|1000')), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final back = loadState(prefs.getString(storageKey)!);
    expect(back.reminders, isEmpty);
  });

  test('notif postpone shifts the entry dueAt by ~24h', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = AppState();
    state.entries.add(Entry(
      id: 'e1',
      chatId: 'c1',
      type: 'todo',
      ts: 0,
      items: [TodoItem(id: 'i', text: 'task')],
      dueAt: now,
    ));
    await seed(state);

    expect(
        await handleSnoozeResponse(resp(notifPostponeAction, 'e1|$now')),
        isTrue);

    final prefs = await SharedPreferences.getInstance();
    final back = loadState(prefs.getString(storageKey)!);
    expect(back.entries.single.dueAt!, greaterThan(now + 23 * 3600 * 1000));
  });

  test('unknown action and bad payload return false', () async {
    expect(await handleSnoozeResponse(resp('nope', 'e1|1')), isFalse);
    expect(await handleSnoozeResponse(resp(notifDoneAction, '')), isFalse);
    expect(await handleSnoozeResponse(resp(notifDoneAction, 'garbage')), isFalse);
  });

  test('legacy snooze ids still work', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = AppState();
    state.entries.add(Entry(
      id: 'e1',
      chatId: 'c1',
      type: 'todo',
      ts: 0,
      items: [TodoItem(id: 'i', text: 'task')],
      dueAt: now,
    ));
    await seed(state);

    expect(await handleSnoozeResponse(resp('tn_snooze_10', 'e1|$now')), isTrue);
  });
}
