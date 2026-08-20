import 'package:flutter/foundation.dart';

import 'i18n.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';

class AppModel extends ChangeNotifier {
  AppModel({AppState? state}) : state = state ?? AppState() {
    _reloadLanguage();
  }

  final AppState state;
  late String Function(String, [List<String>?]) tr;

  Palette get p => paletteFor(state.theme);

  void _reloadLanguage() {
    tr = makeTranslator(state.lang);
  }

  Future<void> load() async {
    final loaded = await AppState.load();
    state
      ..theme = loaded.theme
      ..lang = loaded.lang
      ..chats.addAll(loaded.chats)
      ..entries.addAll(loaded.entries)
      ..reminders.addAll(loaded.reminders);
    _reloadLanguage();
    notifyListeners();
  }

  Future<void> save() => state.save();

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