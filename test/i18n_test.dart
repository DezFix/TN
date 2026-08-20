import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/i18n.dart';

void main() {
  test('all languages have the same keys', () {
    final base = strings['ru']!.keys.toSet();
    for (final entry in strings.entries) {
      expect(entry.value.keys.toSet(), base, reason: 'lang ${entry.key}');
    }
  });

  test('translator returns ru by default', () {
    final tr = makeTranslator('ru');
    expect(tr('app_title'), 'Заметки');
    expect(tr('today'), 'Сегодня');
  });

  test('translator formats placeholders', () {
    final tr = makeTranslator('ru');
    expect(tr('todo_progress', ['2', '5']), '☑ 2/5');
    expect(tr('voice_preview', ['7']), '🎙 Голосовое, 7 сек');
    expect(makeTranslator('en')('forwarded_to', ['Идеи']), 'Forwarded to “Идеи”');
  });

  test('unknown key returns the key itself', () {
    expect(makeTranslator('en')('no_such_key'), 'no_such_key');
  });

  test('unknown language falls back to ru', () {
    expect(makeTranslator('zz')('app_title'), 'Заметки');
  });
}