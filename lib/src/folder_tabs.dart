import 'package:shared_preferences/shared_preferences.dart';

/// Visibility and order of the built-in folder tabs (smart tasks/notes,
/// tags, agenda, calendar) plus the user's own folders.
class FolderTabs {
  static const orderKey = 'tn-folder-tabs-order';

  static const builtin = [
    'smart_tasks',
    'smart_notes',
    'tags',
    'agenda',
    'calendar',
  ];

  static const _prefKeys = {
    'smart_tasks': 'tn-smartfolder-tasks',
    'smart_notes': 'tn-smartfolder-notes',
    'tags': 'tn-smartfolder-tags',
    'agenda': 'tn-smartfolder-agenda',
    'calendar': 'tn-smartfolder-calendar',
  };

  static bool isBuiltin(String id) => builtin.contains(id);

  /// Built-in tabs default to visible; user folders are not in this map.
  static Future<Map<String, bool>> loadEnabled() async {
    final out = {for (final id in builtin) id: true};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in builtin) {
        out[id] = prefs.getBool(_prefKeys[id]!) ?? true;
      }
    } catch (_) {}
    return out;
  }

  static Future<void> setEnabled(String id, bool value) async {
    final key = _prefKeys[id];
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  /// Saved order merged with new/deleted user folders.
  ///
  /// The first launch (no saved order) keeps the familiar layout: smart
  /// tasks/notes, then user folders, then tags, agenda and calendar.
  static Future<List<String>> loadOrder(List<String> folderIds) async {
    final defaults = [
      'smart_tasks',
      'smart_notes',
      ...folderIds,
      'tags',
      'agenda',
      'calendar',
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(orderKey) ?? const <String>[];
      if (saved.isEmpty) return defaults;
      final valid = {...builtin, ...folderIds};
      final out = <String>[];
      for (final id in saved) {
        if (valid.contains(id) && !out.contains(id)) out.add(id);
      }
      for (final id in defaults) {
        if (!out.contains(id)) out.add(id);
      }
      return out;
    } catch (_) {
      return defaults;
    }
  }

  static Future<void> saveOrder(List<String> order) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(orderKey, order);
    } catch (_) {}
  }

  /// Keep the user-folder segment in sync when folders are reordered/deleted
  /// in the dedicated folder editor, without touching built-in positions.
  static Future<void> syncFolderOrder(List<String> folderIds) async {
    final current = await loadOrder(folderIds);
    var i = 0;
    final out = <String>[];
    for (final id in current) {
      out.add(isBuiltin(id) ? id : folderIds[i++]);
    }
    await saveOrder(out);
  }
}
