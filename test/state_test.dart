import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';

void main() {
  test('extractTags: unique, lowercase, cyrillic ok', () {
    expect(extractTags('Привет #Важно и #важно #два'), ['важно', 'два']);
    expect(extractTags('без тегов'), isEmpty);
  });

  test('uid generates unique ids', () {
    expect(uid('e'), isNot(uid('e')));
  });

  test('json roundtrip keeps everything', () {
    final s = AppState();
    s.folders.add(Folder(id: 'f1', name: 'Работа'));
    s.chats.add(Chat(
        id: 'c1',
        name: 'Идеи',
        color: '#2AABEE',
        icon: '💡',
        pinned: true,
        folderId: 'f1'));
    s.entries.add(Entry(
        id: 'e1', chatId: 'c1', type: 'text', ts: 1, text: 'хелло #тег', tags: ['тег']));
    s.entries.add(Entry(
        id: 'e2',
        chatId: 'c1',
        type: 'todo',
        ts: 2,
        items: [TodoItem(id: 't1', text: 'купить', done: true)]));
    s.entries.add(Entry(
        id: 'e3',
        chatId: 'c1',
        type: 'audio',
        ts: 3,
        media: 'a.m4a',
        duration: 5,
        waveform: [10, 50, 90]));
    s.entries.add(Entry(
        id: 'e4',
        chatId: 'c1',
        type: 'text',
        ts: 4,
        text: 'отложка',
        scheduledAt: 9999999999999));
    s.entries.add(Entry(
        id: 'e5',
        chatId: 'c1',
        type: 'text',
        ts: 5,
        text: 'зарядка',
        recurrence: 'weekly',
        recurrenceDays: [1, 3, 5],
        scheduledAt: 9999999999999));
    s.theme = 'dark';
    s.lang = 'en';

    final s2 = AppState()..loadFromJson(s.toJson());
    expect(s2.folders.length, 1);
    expect(s2.folders[0].name, 'Работа');
    expect(s2.chats.length, 1);
    expect(s2.chats[0].name, 'Идеи');
    expect(s2.chats[0].icon, '💡');
    expect(s2.chats[0].pinned, isTrue);
    expect(s2.chats[0].folderId, 'f1');
    expect(s2.theme, 'dark');
    expect(s2.lang, 'en');
    expect(s2.entriesFor('c1').length, 5);
    final todo = s2.entries.firstWhere((e) => e.type == 'todo');
    expect(todo.items!.single.done, isTrue);
    expect(todo.items!.single.text, 'купить');
    final audio = s2.entries.firstWhere((e) => e.type == 'audio');
    expect(audio.duration, 5);
    expect(audio.media, 'a.m4a');
    expect(audio.waveform, [10, 50, 90]);
    final sched = s2.entries.firstWhere((e) => e.id == 'e4');
    expect(sched.isScheduled, isTrue);
    expect(sched.scheduledAt, 9999999999999);
    final weekly = s2.entries.firstWhere((e) => e.id == 'e5');
    expect(weekly.recurrence, 'weekly');
    expect(weekly.recurrenceDays, [1, 3, 5]);
  });

  test('nextOccurrenceMs: daily moves one day ahead at same time', () {
    final base = DateTime(2026, 8, 21, 9, 30).millisecondsSinceEpoch;
    final e = Entry(
        id: 'x',
        chatId: 'c1',
        type: 'text',
        ts: base,
        recurrence: 'daily',
        scheduledAt: base);
    final next = DateTime.fromMillisecondsSinceEpoch(nextOccurrenceMs(e));
    expect(next.day, 22);
    expect(next.hour, 9);
    expect(next.minute, 30);
  });

  test('nextOccurrenceMs: weekly picks next selected weekday', () {
    // 2026-08-21 is a Friday (weekday 5).
    final friday = DateTime(2026, 8, 21, 18, 0).millisecondsSinceEpoch;
    final e = Entry(
        id: 'x',
        chatId: 'c1',
        type: 'text',
        ts: friday,
        recurrence: 'weekly',
        recurrenceDays: [1, 7], // Mon + Sun
        scheduledAt: friday);
    final next = DateTime.fromMillisecondsSinceEpoch(nextOccurrenceMs(e));
    expect(next.weekday, 7); // Sunday
    expect(next.day, 23);
    expect(next.hour, 18);
  });

  test('dueScheduledEntries finds only due messages', () {
    final s = AppState();
    final now = DateTime.now().millisecondsSinceEpoch;
    s.entries.add(Entry(id: 'past', chatId: 'c1', type: 'text', ts: now - 5000, scheduledAt: now - 1000));
    s.entries.add(Entry(id: 'future', chatId: 'c1', type: 'text', ts: now, scheduledAt: now + 60000));
    s.entries.add(Entry(id: 'plain', chatId: 'c1', type: 'text', ts: now));
    final model = AppModel(state: s);
    expect(model.dueScheduledEntries().map((e) => e.id), ['past']);
  });

  test('entriesFor sorts by ts ascending', () {
    final s = AppState();
    s.entries.add(Entry(id: 'a', chatId: 'c1', type: 'text', ts: 30));
    s.entries.add(Entry(id: 'b', chatId: 'c1', type: 'text', ts: 10));
    s.entries.add(Entry(id: 'c', chatId: 'c2', type: 'text', ts: 20));
    final list = s.entriesFor('c1');
    expect(list.map((e) => e.id), ['b', 'a']);
  });

  test('search matches text, tags and todo items', () {
    final s = AppState();
    s.entries.add(Entry(
        id: 'e1', chatId: 'c1', type: 'text', ts: 1, text: 'Купить молоко', tags: []));
    s.entries.add(Entry(
        id: 'e2', chatId: 'c1', type: 'text', ts: 2, text: 'План на день', tags: ['важно']));
    s.entries.add(Entry(
        id: 'e3',
        chatId: 'c1',
        type: 'todo',
        ts: 3,
        items: [TodoItem(id: 't1', text: 'Позвонить маме')]));
    expect(s.searchEntries('молоко').map((e) => e.id), ['e1']);
    expect(s.searchEntries('важно').map((e) => e.id), ['e2']);
    expect(s.searchEntries('позвонить').map((e) => e.id), ['e3']);
    expect(s.searchEntries('нет_такого'), isEmpty);
  });
}