import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';

String tr(String k, [List<String>? args]) {
  const m = {
    'board_idea': 'Идея',
    'board_work': 'В работе',
    'board_done': 'Готово',
  };
  return m[k] ?? k;
}

void main() {
  test('kanban defaults resolve to idea/work/done', () {
    final c = Chat(id: 'c1', name: 'Доска', color: '#2AABEE', kind: 'kanban');
    final boards = c.effectiveBoard(tr);
    expect(boards.map((b) => b.id), ['idea', 'work', 'done']);
    expect(boards.map((b) => b.name), ['Идея', 'В работе', 'Готово']);
  });

  test('legacy entry without boardId lives in first column', () {
    final c = Chat(id: 'c1', name: 'Доска', color: '#2AABEE', kind: 'kanban');
    final e = Entry(id: 'e1', chatId: 'c1', type: 'text', ts: 1, text: 'hi');
    expect(resolvedBoardId(e, c, tr), 'idea');
    expect(nextBoardId(e, c, tr), 'work');
  });

  test('swipe forward stops at last column (no wrap)', () {
    final c = Chat(id: 'c1', name: 'Доска', color: '#2AABEE', kind: 'kanban');
    final e = Entry(id: 'e1', chatId: 'c1', type: 'text', ts: 1, boardId: 'work');
    expect(nextBoardId(e, c, tr), 'done');
    e.boardId = 'done';
    expect(nextBoardId(e, c, tr), isNull);
  });

  test('move to Done auto-checks todo, move back unchecks', () {
    final c = Chat(id: 'c1', name: 'Доска', color: '#2AABEE', kind: 'kanban');
    final e = Entry(
      id: 'e1',
      chatId: 'c1',
      type: 'todo',
      ts: 1,
      items: [TodoItem(id: 't1', text: 'a'), TodoItem(id: 't2', text: 'b')],
    );
    final prev = moveEntryToBoard(e, c, 'done', tr);
    expect(prev, 'idea');
    expect(e.boardId, 'done');
    expect(e.items!.every((i) => i.done), isTrue);
    expect(e.isDone, isTrue);

    moveEntryToBoard(e, c, 'work', tr);
    expect(e.boardId, 'work');
    expect(e.items!.every((i) => !i.done), isTrue);
  });

  test('custom columns roundtrip via json', () {
    final s = AppState();
    final c = Chat(id: 'c1', name: 'Доска', color: '#2AABEE', kind: 'kanban');
    c.board = [BoardColumn(id: 'idea', name: 'Идея'), BoardColumn(id: 'b-x', name: 'Моя')];
    s.chats.add(c);
    s.entries.add(Entry(id: 'e1', chatId: 'c1', type: 'text', ts: 1, boardId: 'b-x'));
    final s2 = AppState()..loadFromJson(s.toJson());
    expect(s2.chats.single.board!.length, 2);
    expect(s2.chats.single.board!.last.name, 'Моя');
    expect(s2.entries.single.boardId, 'b-x');
  });

  test('text cards keep boardId when copied', () {
    final e = Entry(id: 'e1', chatId: 'c1', type: 'text', ts: 1, boardId: 'work');
    final copy = e.copyForForward('c2');
    expect(copy.boardId, 'work');
  });

  test('ordinary board moves preserve the task deadline', () {
    final c = Chat(id: 'c1', name: 'Доска', color: '#2AABEE', kind: 'kanban');
    final dueAt = DateTime(2030, 1, 2, 9).millisecondsSinceEpoch;
    final e = Entry(
      id: 'e1',
      chatId: 'c1',
      type: 'todo',
      ts: 1,
      dueAt: dueAt,
      items: [TodoItem(id: 't1', text: 'a')],
    );

    moveEntryToBoard(e, c, 'work', tr);
    expect(e.dueAt, dueAt);
    moveEntryToBoard(e, c, 'done', tr);
    expect(e.dueAt, dueAt);
  });
}
