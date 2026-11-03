import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/folder_tabs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('default order keeps smart folders, user folders, then shortcuts', () async {
    final order = await FolderTabs.loadOrder(['f1', 'f2']);
    expect(order, [
      'smart_tasks',
      'smart_notes',
      'f1',
      'f2',
      'tags',
      'agenda',
      'calendar',
    ]);
  });

  test('saved order wins and deleted folders are dropped', () async {
    await FolderTabs.saveOrder([
      'calendar',
      'f2',
      'smart_notes',
      'deleted',
      'tags',
      'agenda',
      'smart_tasks',
      'f1',
    ]);
    final order = await FolderTabs.loadOrder(['f1', 'f2']);
    expect(order, [
      'calendar',
      'f2',
      'smart_notes',
      'tags',
      'agenda',
      'smart_tasks',
      'f1',
    ]);
    expect(order, isNot(contains('deleted')));
  });

  test('new folders are appended, built-in toggles persist', () async {
    await FolderTabs.saveOrder(['tags', 'agenda', 'calendar']);
    final order = await FolderTabs.loadOrder(['fresh']);
    expect(order.first, 'tags');
    expect(order, contains('fresh'));

    await FolderTabs.setEnabled('agenda', false);
    final enabled = await FolderTabs.loadEnabled();
    expect(enabled['agenda'], isFalse);
    expect(enabled['calendar'], isTrue);
    expect(enabled['tags'], isTrue);
  });

  test('folder reorder only moves user folder slots', () async {
    await FolderTabs.saveOrder([
      'smart_tasks',
      'f1',
      'f2',
      'tags',
      'calendar',
      'agenda',
      'smart_notes',
    ]);
    await FolderTabs.syncFolderOrder(['f2', 'f1']);
    final order = await FolderTabs.loadOrder(['f2', 'f1']);
    expect(order, [
      'smart_tasks',
      'f2',
      'f1',
      'tags',
      'calendar',
      'agenda',
      'smart_notes',
    ]);
  });
}
