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

  List<Entry> entriesFor(String chatId) =>
      entries.where((e) => e.chatId == chatId).toList()
        ..sort((a, b) => a.ts.compareTo(b.ts));

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
    if (data['theme'] == 'dark') theme = 'dark';
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