import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';

void main() {
  Entry entry({
    String type = 'text',
    String? recurrence,
    List<int>? days,
    int? monthDay,
    int? dueAt,
    bool pinned = false,
    List<TodoItem>? items,
  }) =>
      Entry(
        id: 'e1',
        chatId: 'c1',
        type: type,
        ts: 1000,
        text: 'hello #tag',
        tags: ['tag'],
        items: items,
        dueAt: dueAt,
        recurrence: recurrence,
        recurrenceDays: days,
        monthDay: monthDay,
        pinned: pinned,
      );

  group('copyForForward', () {
    test('keeps monthly recurrence fields (monthDay was dropped before)', () {
      final copy = entry(
              type: 'todo',
              recurrence: 'monthly',
              monthDay: 15,
              dueAt: 5000,
              items: [TodoItem(id: 't', text: 'task')])
          .copyForForward('c2');
      expect(copy.id, isNot('e1'));
      expect(copy.chatId, 'c2');
      expect(copy.recurrence, 'monthly');
      expect(copy.monthDay, 15);
      expect(copy.dueAt, 5000);
      expect(copy.items!.single.text, 'task');
    });

    test('keeps weekly recurrence days', () {
      final copy =
          entry(recurrence: 'weekly', days: [1, 3, 5]).copyForForward('c2');
      expect(copy.recurrence, 'weekly');
      expect(copy.recurrenceDays, [1, 3, 5]);
    });

    test('copies waveform and tags deep enough to be independent', () {
      final src = Entry(
        id: 'a',
        chatId: 'c1',
        type: 'audio',
        ts: 1,
        tags: ['x'],
        waveform: [10, 90],
      );
      final copy = src.copyForForward('c2');
      copy.tags.add('y');
      copy.waveform!.add(50);
      expect(src.tags, ['x']);
      expect(src.waveform, [10, 90]);
    });
  });

  test('entry.pinned survives json roundtrip', () {
    final s = AppState();
    s.entries.add(entry(pinned: true));
    final s2 = AppState()..loadFromJson(s.toJson());
    expect(s2.entries.single.pinned, isTrue);
  });

  test('entriesFor floats pinned entries above newer ones', () {
    final s = AppState();
    s.chats.add(Chat(id: 'c1', name: 'chat', color: '#FFFFFF'));
    s.entries
        .add(Entry(id: 'old', chatId: 'c1', type: 'text', ts: 10));
    s.entries.add(Entry(id: 'new', chatId: 'c1', type: 'text', ts: 20));
    s.entries.firstWhere((e) => e.id == 'old').pinned = true;
    expect(s.entriesFor('c1').map((e) => e.id), ['old', 'new']);
  });
}
