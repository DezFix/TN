import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/undo.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AppModel modelWithEntries() {
    final model = AppModel();
    model.state.chats.add(Chat(id: 'c1', name: 'chat', color: '#FFFFFF'));
    model.state.entries
        .add(Entry(id: 'a', chatId: 'c1', type: 'text', ts: 1, text: 'one'));
    model.state.entries
        .add(Entry(id: 'b', chatId: 'c1', type: 'text', ts: 2, text: 'two'));
    return model;
  }

  test('deleteEntries removes them, restore puts them back', () async {
    final model = modelWithEntries();
    final victims = [
      model.state.entries.firstWhere((e) => e.id == 'a'),
    ];

    expect(await UndoService.deleteEntries(model, victims), isTrue);
    expect(model.state.entries.map((e) => e.id), ['b']);

    await UndoService.restoreEntries(model, victims);
    expect(model.state.entries.map((e) => e.id).toSet(), {'a', 'b'});
  });

  test('restore skips ids that reappeared meanwhile (widget/sync)', () async {
    final model = modelWithEntries();
    final victim = model.state.entries.firstWhere((e) => e.id == 'a');
    await UndoService.deleteEntries(model, [victim]);

    // Same id comes back from an external writer before the undo.
    final external = Entry(id: 'a', chatId: 'c1', type: 'text', ts: 9, text: 'fresh');
    model.state.entries.add(external);

    await UndoService.restoreEntries(model, [victim]);
    final restored = model.state.entries.firstWhere((e) => e.id == 'a');
    expect(restored.text, 'fresh', reason: 'external write must win over undo');
  });

  test('delete of empty list is a no-op returning false', () async {
    final model = modelWithEntries();
    expect(await UndoService.deleteEntries(model, []), isFalse);
  });
}
