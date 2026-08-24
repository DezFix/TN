import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'models.dart';
import 'reminders.dart';
import 'state.dart';
import 'theme.dart';
import 'widget_bridge.dart';

class AppModel extends ChangeNotifier {
  AppModel({AppState? state}) : state = state ?? AppState() {
    _reloadLanguage();
  }

  final AppState state;
  late String Function(String, [List<String>?]) tr;
  int _stamp = DateTime.now().millisecondsSinceEpoch;

  Palette get p => paletteFor(state.theme);

  void _reloadLanguage() {
    tr = makeTranslator(state.lang);
  }

  Future<void> load() async {
    final loaded = await AppState.load();
    state
      ..theme = loaded.theme
      ..lang = loaded.lang
      ..folders.addAll(loaded.folders)
      ..chats.addAll(loaded.chats)
      ..entries.addAll(loaded.entries)
      ..reminders.addAll(loaded.reminders);
    _reloadLanguage();
    _stamp = DateTime.now().millisecondsSinceEpoch;
    rolloverRecurring();
    notifyListeners();
  }

  /// Recurring tasks reset themselves (see rolloverRecurringTasks); after
  /// the reset we re-arm notifications for the new deadlines.
  int rolloverRecurring() {
    final rolled = rolloverRecurringTasks(state.entries, DateTime.now());
    for (final e in rolled) {
      final chat = state.chatById(e.chatId);
      RemindersService.instance.schedule(
        Reminder(id: e.id, chatId: e.chatId, when: e.dueAt!),
        tr('remind_title', [chat?.name ?? 'TN']),
        entryNotifBody(e, tr),
      ).catchError((_) {});
    }
    return rolled.length;
  }

  Future<void> save() async {
    await state.save();
    _stamp = DateTime.now().millisecondsSinceEpoch;
    // Fire-and-forget: the native widget update must not block saving
    // (in tests the method channel has no handler).
    WidgetBridge.refresh().catchError((_) {});
  }

  /// Applies changes written by another writer (home-screen widget) while the
  /// app was in background. Returns true when something was reloaded.
  Future<bool> syncIfExternal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The plugin caches values in memory; native widget writes bypass it.
      await prefs.reload();
      final ext = prefs.getInt('tn-state-stamp') ?? 0;
      if (ext <= _stamp) return false;
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return false;
      state.loadFromJson(raw);
      _reloadLanguage();
      _stamp = ext;
      final rolled = rolloverRecurring();
      if (rolled > 0) {
        await save();
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setTheme(String theme) async {
    state.theme = theme;
    await state.save();
    notifyListeners();
  }

  Future<void> setLang(String lang) async {
    state.lang = lang;
    await state.save();
    _reloadLanguage();
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

String fmtTime(int ts) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}';
}

String fmtDay(int ts, String Function(String) tr) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  if (day == today) return tr('today');
  if (day == today.subtract(const Duration(days: 1))) return tr('yesterday');
  const months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

String entryPreview(Entry e, String Function(String, [List<String>?]) tr) {
  switch (e.type) {
    case 'text':
      return e.text.length > 60 ? e.text.substring(0, 60) : e.text;
    case 'image':
      return tr('photo');
    case 'audio':
      return tr('voice_preview', ['${e.duration ?? 0}']);
    case 'video':
      return tr('video_preview');
    case 'todo':
      final items = e.items ?? const <TodoItem>[];
      final done = items.where((i) => i.done).length;
      return tr('todo_progress', ['$done', '${items.length}']);
  }
  return '';
}

/// Notification body: the actual note/task content, not a generic phrase.
String entryNotifBody(Entry e, String Function(String, [List<String>?]) tr) {
  if (e.type == 'todo') {
    final open = (e.items ?? const <TodoItem>[]).where((i) => !i.done).toList();
    final t = (open.isNotEmpty ? open.map((i) => i.text).join('\n') : e.text).trim();
    if (t.isNotEmpty) return t;
  }
  return entryPreview(e, tr);
}

List<Entry> sortedEntriesFor(AppState state, String chatId) =>
    state.entriesFor(chatId).reversed.toList();