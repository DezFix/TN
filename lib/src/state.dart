import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'models.dart';

class AppState {
  String theme = 'light';
  String lang = 'ru';
  final List<Folder> folders = [];
  final List<Chat> chats = [];
  final List<Entry> entries = [];
  final List<Reminder> reminders = [];

  /// Last error thrown by [save], if any — the UI can surface it instead of
  /// silently losing data (e.g. disk full).
  Object? lastSaveError;

  /// Entries of a chat. If the chat has an enabled auto-collect rule,
  /// matching entries from other chats are merged in (same objects, so
  /// toggling a task works from both places). Pinned entries float to the
  /// top regardless of time order.
  List<Entry> entriesFor(String chatId) {
    final own =
        entries.where((e) => e.chatId == chatId).toList(growable: false);
    final rule = chatById(chatId)?.autoCollect;
    if (rule != null && rule.enabled) {
      final seen = own.map((e) => e.id).toSet();
      for (final c in chats) {
        if (c.id == chatId) continue; // don't pull into itself
        if (c.autoCollect?.enabled ?? false) continue; // no chaining rules
        if (!rule.fromAllChats && c.folderId != rule.sourceFolderId) continue;
        for (final e in entries) {
          if (e.chatId != c.id || seen.contains(e.id)) continue;
          if (_matchesCollectRule(e, rule)) {
            own.add(e);
            seen.add(e.id);
          }
        }
      }
    }
    own.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.ts.compareTo(b.ts);
    });
    return own;
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
    var query = q.toLowerCase();
    // '#tag' restricts the search to hashtag matches.
    final tagOnly = query.startsWith('#');
    if (tagOnly && query.length > 1) query = query.substring(1);
    if (query.isEmpty) return const [];
    final out = <Entry>[];
    for (final e in entries) {
      if (!tagOnly && e.text.toLowerCase().contains(query)) {
        out.add(e);
        continue;
      }
      if (e.tags.any((t) => t.contains(query))) {
        out.add(e);
        continue;
      }
      if (tagOnly) continue;
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
    } catch (e, st) {
      AppLog.error('state.load', e, st);
    }
    return state;
  }

  Future<void> save() async {
    try {
      lastSaveError = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, toJson());
      // Stamp lets the app detect changes made outside this process
      // (e.g. checking a task from the home-screen widget).
      await prefs.setInt('tn-state-stamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e, st) {
      // Never swallow: a failed save used to silently lose user data.
      lastSaveError = e;
      AppLog.error('state.save', e, st);
    }
  }

  /// Last-write-wins merge of a remote snapshot (cloud backup from another
  /// device). Per-record comparison by `updatedAt` for entries and by
  /// identity for chats/folders/reminders: remote adds what we don't have,
  /// overwrites what is newer, and never deletes local records — so pulling
  /// an older backup can no longer wipe recent notes. Local theme/lang win.
  void mergeFromJson(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final remoteFolders = (data['folders'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Folder.fromJson);
    for (final f in remoteFolders) {
      final i = folders.indexWhere((x) => x.id == f.id);
      if (i < 0) {
        folders.add(f);
      } else if (f.name != folders[i].name || f.color != folders[i].color) {
        folders[i]
          ..name = f.name
          ..color = f.color;
      }
    }

    final remoteChats = (data['chats'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Chat.fromJson);
    for (final c in remoteChats) {
      final i = chats.indexWhere((x) => x.id == c.id);
      if (i < 0) {
        chats.add(c);
        continue;
      }
      final local = chats[i];
      // A trashed chat must stay trashed even if the remote copy isn't.
      final deletedAt = local.isTrashed &&
              ((c.deletedAt ?? 0) <= (local.deletedAt ?? 0))
          ? local.deletedAt
          : (local.deletedAt ?? c.deletedAt);
      chats[i] = c
        ..pinned = c.pinned || local.pinned
        ..deletedAt = deletedAt;
    }

    final remoteEntries = (data['entries'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Entry.fromJson);
    for (final e in remoteEntries) {
      final i = entries.indexWhere((x) => x.id == e.id);
      if (i < 0) {
        entries.add(e);
      } else if (e.updatedAt >= entries[i].updatedAt) {
        entries[i] = e;
      }
    }

    final remoteReminders = (data['reminders'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Reminder.fromJson);
    for (final r in remoteReminders) {
      if (!reminders.any((x) => x.id == r.id && x.when == r.when)) {
        reminders.add(r);
      }
    }
  }
}