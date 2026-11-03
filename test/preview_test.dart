import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/i18n.dart';
import 'package:tn/src/models.dart';

void main() {
  final tr = makeTranslator('ru');

  Entry todo(List<TodoItem> items, {String text = ''}) => Entry(
        id: 'e',
        chatId: 'c',
        type: 'todo',
        ts: 1,
        text: text,
        items: items,
      );

  test('task preview shows the task text, not a 0/1 counter', () {
    final e = todo([TodoItem(id: 't', text: 'Купить молоко')]);
    expect(entryPreview(e, tr), 'Купить молоко');
    expect(entryPreview(e, tr), isNot(contains('0/1')));
  });

  test('task preview includes priority and progress for lists', () {
    final e = todo([
      TodoItem(id: 'a', text: 'Купить молоко', priority: 2, done: true),
      TodoItem(id: 'b', text: 'Позвонить маме', priority: 2),
    ]);
    expect(entryPreview(e, tr), 'Срочная: Позвонить маме · 1/2');
    expect(entryPriority(e), 2);
  });

  test('completed list keeps the text and falls back to its priority', () {
    final e = todo([
      TodoItem(id: 'a', text: 'Сделано', priority: 1, done: true),
    ]);
    expect(entryPreview(e, tr), 'Важная: Сделано');
    expect(entryPriority(e), 1);
  });

  test('legacy todo without items falls back to its text', () {
    final e = todo(const [], text: 'Старая задача');
    expect(entryPreview(e, tr), 'Старая задача');
    expect(entryPriority(e), 0);
  });
}
