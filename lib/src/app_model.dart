import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_bridge.dart';

import 'chat_lock.dart';
import 'i18n.dart';
import 'models.dart';
import 'reminders.dart';
import 'state.dart';
import 'theme.dart';

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
    await ChatLock.init();
    final loaded = await AppState.load();
    state
      ..theme = loaded.theme
      ..lang = loaded.lang
       ..stateUpdatedAt = loaded.stateUpdatedAt
      ..folders.clear()
      ..folders.addAll(loaded.folders)
      ..chats.clear()
      ..chats.addAll(loaded.chats)
      ..entries.clear()
      ..entries.addAll(loaded.entries)
      ..reminders.clear()
      ..reminders.addAll(loaded.reminders);
    _reloadLanguage();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tn-widget-lang', state.lang);
    } catch (_) {}
    WidgetBridge.refresh().catchError((_) {});
    _stamp = DateTime.now().millisecondsSinceEpoch;
    final rolled = rolloverRecurring();
    if (rolled > 0) {
      await save();
    }
    await rescheduleAlarms();
    notifyListeners();
  }

  /// Rebuilds every pending alarm from the state — the source of truth.
  /// Heals lost reminders after plugin hiccups, permission grants, app
  /// updates or anything else that could have silently dropped them.
  /// Trashed chats are skipped: their reminders were cancelled on delete,
  /// and entry deadlines must not keep firing either.
  Future<void> rescheduleAlarms() async {
    try {
      await RemindersService.instance.cancelAll();
    } catch (_) {}
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in state.reminders) {
      if (r.when <= now) continue;
      final chat = state.chatById(r.chatId);
      if (chat == null || chat.isTrashed || !chat.notificationsEnabled) {
        continue;
      }
      await RemindersService.instance.schedule(
        r,
        tr('remind_title', [chat.name]),
        tr('remind_body'),
        actionLabels: [tr('notif_postpone'), tr('notif_done')],
      );
    }
    for (final e in state.entries) {
      if (e.dueAt == null || e.dueAt! <= now) continue;
      // Done tasks (incl. just-checked recurring) must not ring.
      if (e.isDone) continue;
      final chat = state.chatById(e.chatId);
      if (chat == null || chat.isTrashed || !chat.notificationsEnabled) {
        continue;
      }
      await RemindersService.instance.schedule(
        Reminder(id: e.id, chatId: e.chatId, when: e.dueAt!),
        tr('remind_title', [chat.name]),
        entryNotifBody(e, tr),
        actionLabels: [tr('notif_postpone'), tr('notif_done')],
      );
    }
  }

  /// Shifts a due moment (custom reminder or todo deadline) into the future
  /// by [minutes] from now. [key] is DueItem's `id|when`. Returns true when
  /// something was rescheduled.
  Future<bool> snoozeByKey(String key, int minutes) async {
    final sep = key.lastIndexOf('|');
    if (sep <= 0) return false;
    final id = key.substring(0, sep);
    final when = int.tryParse(key.substring(sep + 1));
    if (when == null) return false;
    final target = DateTime.now().millisecondsSinceEpoch + minutes * 60 * 1000;
    var hit = false;
    for (final r in List.of(state.reminders)) {
      if (r.id == id && r.when == when) {
        state.reminders.remove(r);
        state.reminders.add(Reminder(id: r.id, chatId: r.chatId, when: target));
        hit = true;
        break;
      }
    }
    if (!hit) {
      for (final e in state.entries) {
        if (e.id == id && e.dueAt == when) {
          e.dueAt = target;
          e.updatedAt = DateTime.now().millisecondsSinceEpoch;
          hit = true;
          break;
        }
      }
    }
    if (!hit) return false;
    await save();
    await rescheduleAlarms();
    notifyListeners();
    return true;
  }

  /// Recurring tasks reset themselves (see rolloverRecurringTasks); after
  /// the reset we re-arm notifications for the new deadlines.
  int rolloverRecurring() {
    final rolled = rolloverRecurringTasks(state.entries, DateTime.now());
    for (final e in rolled) {
      final chat = state.chatById(e.chatId);
      if (chat == null || chat.isTrashed || !chat.notificationsEnabled) {
        continue;
      }
      RemindersService.instance
          .schedule(
        Reminder(id: e.id, chatId: e.chatId, when: e.dueAt!),
        tr('remind_title', [chat.name]),
        entryNotifBody(e, tr),
        actionLabels: [tr('notif_postpone'), tr('notif_done')],
          )
          .catchError((_) => false);
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
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('tn-widget-lang', state.lang);
      } catch (_) {}
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tn-widget-lang', lang);
    } catch (_) {}
    WidgetBridge.refresh().catchError((_) {});
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

String fmtTime(int ts) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}';
}

String fmtDay(int ts, String Function(String, [List<String>?]) tr) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  if (day == today) return tr('today');
  if (day == DateTime(now.year, now.month, now.day - 1)) {
    return tr('yesterday');
  }
  // Month names come from the i18n table — the old hardcoded Russian list
  // leaked into every interface language.
  final label = '${dt.day} ${tr('month_${dt.month}')}';
  return dt.year == now.year ? label : '$label ${dt.year}';
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
    case 'doc':
      final name = (e.mediaName ?? '').trim();
      return name.isEmpty ? tr('attach_doc') : name;
    case 'todo':
      final items = e.items ?? const <TodoItem>[];
      if (items.isEmpty) {
        final t = e.text.trim();
        return t.isEmpty ? tr('todo') : t;
      }
      final open = items.where((i) => !i.done).toList();
      final pool = open.isNotEmpty ? open : items;
      final roots = pool.where((i) => i.parentId == null).toList();
      final pick = roots.isNotEmpty ? roots.first : pool.first;

      // Priority of the task itself, not a "0/1" counter: the list/calendar
      // used to replace every task title with a progress badge.
      var prio = 0;
      for (final i in pool) {
        if (i.priority > prio) prio = i.priority;
      }
      final label = prio > 0 ? '${tr('priority_$prio')}: ' : '';

      var text = pick.text.trim();
      if (text.isEmpty) text = e.text.trim();
      if (text.isEmpty) {
        final done = items.where((i) => i.done).length;
        return tr('todo_progress', ['$done', '${items.length}']);
      }
      if (text.length > 60) text = text.substring(0, 60);
      final done = items.where((i) => i.done).length;
      final progress = items.length > 1 ? ' · $done/${items.length}' : '';
      return '$label$text$progress';
  }
  return '';
}

/// Highest priority among the open tasks of [e] (falls back to all items).
int entryPriority(Entry e) {
  if (e.type != 'todo') return 0;
  final items = e.items ?? const <TodoItem>[];
  final open = items.where((i) => !i.done).toList();
  final pool = open.isNotEmpty ? open : items;
  var prio = 0;
  for (final i in pool) {
    if (i.priority > prio) prio = i.priority;
  }
  return prio;
}

/// Notification body: the actual note/task content, not a generic phrase.
String entryNotifBody(Entry e, String Function(String, [List<String>?]) tr) {
  if (e.type == 'todo') {
    final open = (e.items ?? const <TodoItem>[]).where((i) => !i.done).toList();
    final t = (open.isNotEmpty ? open.map((i) => i.text).join('\n') : e.text)
        .trim();
    if (t.isNotEmpty) return t;
  }
  return entryPreview(e, tr);
}

List<Entry> sortedEntriesFor(AppState state, String chatId) =>
    state.entriesFor(chatId).reversed.toList();
