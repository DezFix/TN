import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppState {
  String theme = 'light';
  String lang = 'ru';
  final List<Folder> folders = [];
  final List<Chat> chats = [];
  final List<Entry> entries = [];
  final List<Reminder> reminders = [];

  /// Entries of a chat. If the chat has an enabled auto-collect rule,
  /// matching entries from other chats are merged in (same objects, so
  /// toggling a task works from both places).
  List<Entry> entriesFor(String chatId) {
    final own = entries.where((e) => e.chatId == chatId).toList();
    final rule = chatById(chatId)?.autoCollect;
    if (rule == null || !rule.enabled) {
      return own..sort((a, b) => a.ts.compareTo(b.ts));
    }
    final out = <Entry>[...own];
    final seen = out.map((e) => e.id).toSet();
    for (final c in chats) {
      if (c.id == chatId) continue; // don't pull into itself
      if (c.autoCollect?.enabled ?? false) continue; // no chaining rules
      if (!rule.fromAllChats && c.folderId != rule.sourceFolderId) continue;
      for (final e in entries) {
        if (e.chatId != c.id || seen.contains(e.id)) continue;
        if (_matchesCollectRule(e, rule)) {
          out.add(e);
          seen.add(e.id);
        }
      }
    }
    return out..sort((a, b) => a.ts.compareTo(b.ts));
  }

  bool _matchesCollectRule(Entry e, AutoCollect r) {
    switch (r.typeFilter) {
      case 'todo':
        if (e.type != 'todo') return false;
      case 'note':
        if (e.type == 'todo') return false;
    }
    if (r.dueFilter == 'today' && e.type == 'todo') {
      final due = e.dueAt;
      // "today" surfaces overdue tasks as well — they still need doing.
      if (due != null && due > endOfTodayMillis()) return false;
    }
    return true;
  }

  static int endOfTodayMillis() {
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return start + 24 * 60 * 60 * 1000 - 1;
  }

  Chat? chatById(String id) {
    for (final c in chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  Folder? folderById(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<Entry> searchEntries(String q) {
    final query = q.toLowerCase();
    final out = <Entry>[];
    for (final e in entries) {
      if (e.text.toLowerCase().contains(query)) {
        out.add(e);
        continue;
      }
      if (e.tags.any((t) => t.contains(query))) {
        out.add(e);
        continue;
      }
      final items = e.items ?? const <TodoItem>[];
      if (items.any((i) => i.text.toLowerCase().contains(query))) {
        out.add(e);
      }
    }
    return out;
  }

  void loadFromJson(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    folders
      ..clear()
      ..addAll((data['folders'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Folder.fromJson));
    chats
      ..clear()
      ..addAll((data['chats'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Chat.fromJson));
    entries
      ..clear()
      ..addAll((data['entries'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Entry.fromJson));
    reminders
      ..clear()
      ..addAll((data['reminders'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Reminder.fromJson));
    // 'system' theme option was removed; legacy value maps to dark.
    theme = data['theme'] == 'light' ? 'light' : 'dark';
    if (data['lang'] is String) lang = data['lang'] as String;
  }

  String toJson() => jsonEncode({
        'theme': theme,
        'lang': lang,
        'folders': folders.map((f) => f.toJson()).toList(),
        'chats': chats.map((c) => c.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'reminders': reminders.map((r) => r.toJson()).toList(),
      });

  static Future<AppState> load() async {
    final state = AppState();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) state.loadFromJson(raw);
    } catch (_) {}
    return state;
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, toJson());
      // Stamp lets the app detect changes made outside this process
      // (e.g. checking a task from the home-screen widget).
      await prefs.setInt('tn-state-stamp', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}