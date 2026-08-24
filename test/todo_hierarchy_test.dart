import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/models.dart';

void main() {
  group('TodoItem hierarchy', () {
    test('json round-trips parentId', () {
      final item = TodoItem(id: 't1', text: 'root', parentId: 't0');
      final restored = TodoItem.fromJson(item.toJson());
      expect(restored.parentId, 't0');
    });

    test('legacy json without pid stays root', () {
      final restored = TodoItem.fromJson({'id': 't1', 'text': 'x', 'done': true});
      expect(restored.parentId, isNull);
      expect(restored.done, isTrue);
    });

    test('toJson omits pid for roots', () {
      expect(TodoItem(id: 'a', text: 'x').toJson().containsKey('pid'), isFalse);
    });
  });

  group('toggleTodoCascade', () {
    List<TodoItem> fixture() => [
          TodoItem(id: 'p', text: 'parent'),
          TodoItem(id: 'c1', text: 'sub 1', parentId: 'p'),
          TodoItem(id: 'g', text: 'deep', parentId: 'c1'),
          TodoItem(id: 'solo', text: 'standalone'),
        ];

    test('checking parent checks whole subtree but not other roots', () {
      final items = fixture();
      toggleTodoCascade(items, 'p');
      expect(
          items.where((i) => i.id != 'solo').map((i) => i.done),
          everyElement(isTrue));
      expect(items.firstWhere((i) => i.id == 'solo').done, isFalse);
    });

    test('unchecking parent unchecks subtree', () {
      final items = fixture()..forEach((i) => i.done = true);
      toggleTodoCascade(items, 'p');
      expect(
          items.where((i) => i.id != 'solo').map((i) => i.done),
          everyElement(isFalse));
      expect(items.firstWhere((i) => i.id == 'solo').done, isTrue);
    });

    test('child toggle does not touch parent or siblings', () {
      final items = fixture();
      toggleTodoCascade(items, 'c1');
      expect(items.firstWhere((i) => i.id == 'p').done, isFalse);
      expect(items.firstWhere((i) => i.id == 'g').done, isTrue);
      expect(items.firstWhere((i) => i.id == 'solo').done, isFalse);
    });

    test('unknown id returns false without changes', () {
      final items = fixture();
      expect(toggleTodoCascade(items, 'nope'), isFalse);
      expect(items.any((i) => i.done), isFalse);
    });
  });

  group('removeTodoItem', () {
    test('deleting parent re-parents children to root', () {
      final items = [
        TodoItem(id: 'p', text: 'p'),
        TodoItem(id: 'c', text: 'c', parentId: 'p'),
        TodoItem(id: 'g', text: 'g', parentId: 'c'),
      ];
      expect(removeTodoItem(items, 'p'), isTrue);
      expect(items.length, 2);
      expect(items.firstWhere((i) => i.id == 'c').parentId, isNull);
      // grandchild keeps its direct parent
      expect(items.firstWhere((i) => i.id == 'g').parentId, 'c');
    });

    test('unknown id returns false', () {
      expect(removeTodoItem([TodoItem(id: 'a', text: 'x')], 'zz'), isFalse);
    });
  });
}
