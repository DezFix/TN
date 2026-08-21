import 'dart:async';

import 'package:flutter/foundation.dart';

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
  Timer? _schedTicker;

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
    notifyListeners();
  }

  Future<void> save() async {
    await state.save();
    // Fire-and-forget: the native widget update must not block saving
    // (in tests the method channel has no handler).
    unawaited(WidgetBridge.refresh());
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

  // ---------------- scheduled messages ----------------

  void startScheduler() {
    _schedTicker?.cancel();
    releaseDueScheduled(notify: false);
    _schedTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      releaseDueScheduled();
    });
  }

  void stopScheduler() {
    _schedTicker?.cancel();
    _schedTicker = null;
  }

  List<Entry> dueScheduledEntries({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return state.entries
        .where((e) => e.scheduledAt != null && e.scheduledAt! <= now)
        .toList();
  }

  Future<void> releaseDueScheduled({bool notify = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = dueScheduledEntries(nowMs: now);
    if (due.isEmpty) return;
    for (final e in due) {
      if (e.recurrence != null) {
        // Recurring: spawn a real message copy, move template to next slot.
        state.entries.add(Entry(
          id: uid('e'),
          chatId: e.chatId,
          type: e.type,
          ts: e.scheduledAt!,
          text: e.text,
          tags: List.of(e.tags),
          media: e.media,
          mediaName: e.mediaName,
          mediaSize: e.mediaSize,
          duration: e.duration,
          items: e.items
              ?.map((i) => TodoItem(id: i.id, text: i.text, done: i.done))
              .toList(),
          waveform: e.waveform == null ? null : List.of(e.waveform!),
        ));
        final next = nextOccurrenceMs(e);
        e.scheduledAt = next;
        await RemindersService.instance.schedule(
          Reminder(id: e.id, chatId: e.chatId, when: next),
          tr('sched_notif_title'),
          tr('sched_notif_body', [_chatName(e.chatId)]),
        );
        continue;
      }
      e.scheduledAt = null;
      // If released long after the target time, the fallback notification
      // has most likely already fired — don't duplicate it.
      if (now - e.ts < 90 * 1000) {
        await RemindersService.instance.cancelById(e.id.hashCode);
        await RemindersService.instance.showNow(
          id: e.id.hashCode,
          title: tr('sched_notif_title'),
          body: tr('sched_notif_body', [_chatName(e.chatId)]),
        );
      }
    }
    await state.save();
    if (notify) notifyListeners();
  }

  String _chatName(String chatId) {
    final chat = state.chatById(chatId);
    return chat?.name ?? '';
  }
}

/// Next fire time for a recurring entry. Daily: same time tomorrow.
/// Weekly: first selected weekday after the current occurrence.
int nextOccurrenceMs(Entry e) {
  final cur = DateTime.fromMillisecondsSinceEpoch(e.scheduledAt ?? e.ts);
  var candidate = cur.add(const Duration(days: 1));
  if (e.recurrence == 'weekly') {
    final days = e.recurrenceDays ?? const <int>[];
    var guard = 0;
    while (!days.contains(candidate.weekday) && guard < 8) {
      candidate = candidate.add(const Duration(days: 1));
      guard++;
    }
  }
  return DateTime(candidate.year, candidate.month, candidate.day, cur.hour, cur.minute)
      .millisecondsSinceEpoch;
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
  return '${dt.day} $months[${dt.month - 1}]';
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

List<Entry> sortedEntriesFor(AppState state, String chatId) =>
    state.entriesFor(chatId).reversed.toList();