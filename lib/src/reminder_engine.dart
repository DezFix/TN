import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_model.dart';
import 'banner.dart';
import 'models.dart';
import 'reminders.dart';
import '../screens/chat_screen.dart';
import 'sound.dart';
import 'win_toast.dart';

/// One reminder that is due right now, already formatted for delivery.
@visibleForTesting
class DueItem {
  DueItem({required this.key, required this.chatId, required this.when, required this.title, required this.body});

  /// Unique per (reminder id, target time) so a rescheduled reminder fires
  /// again but the same deadline never fires twice.
  final String key;
  final String chatId;

  /// Target time — used to dedupe the same deadline reached through both a
  /// custom reminder and its todo entry.
  final int when;
  final String title;
  final String body;
}

const int _missedWindowMs = 24 * 60 * 60 * 1000;

/// Pure scan of the state: custom reminders + todo deadlines that are due
/// within the last [_missedWindowMs]. Anything older is considered stale and
/// silently skipped (like Telegram showing only recent missed messages).
@visibleForTesting
List<DueItem> collectDue({
  required List<Reminder> reminders,
  required List<Entry> entries,
  required String Function(String chatId) chatNameOf,
  required String Function(String, [List<String>?]) tr,
  required int now,
}) {
  final floor = now - _missedWindowMs;
  final out = <DueItem>[];
  final seen = <String>{};
  void add(DueItem d) {
    // One delivery per (chat, deadline): the same due moment often exists
    // both as a custom reminder and as the todo entry's dueAt.
    if (!seen.add('${d.chatId}|${d.when}')) return;
    out.add(d);
  }

  for (final r in reminders) {
    if (r.when > now || r.when < floor) continue;
    add(DueItem(
      key: '${r.id}|${r.when}',
      chatId: r.chatId,
      when: r.when,
      title: tr('remind_title', [chatNameOf(r.chatId)]),
      body: tr('remind_body'),
    ));
  }
  for (final e in entries) {
    if (e.type != 'todo' || e.dueAt == null) continue;
    if (e.dueAt! > now || e.dueAt! < floor) continue;
    add(DueItem(
      key: '${e.id}|${e.dueAt}',
      chatId: e.chatId,
      when: e.dueAt!,
      title: tr('remind_title', [chatNameOf(e.chatId)]),
      body: entryNotifBody(e, tr),
    ));
  }
  return out;
}

/// Telegram-style reminder delivery for desktop: a timer scans the state
/// every few seconds; due items become an in-app banner while the window is
/// focused or a system toast (with sound) otherwise. This replaces the
/// unreliable native scheduled toasts on Windows.
class ReminderEngine {
  static final ReminderEngine instance = ReminderEngine._();

  ReminderEngine._();

  AppModel? _model;
  GlobalKey<NavigatorState>? _navKey;
  Timer? _timer;
  final Set<String> _fired = {};

  bool get running => _timer != null;

  void start(AppModel model, GlobalKey<NavigatorState> navKey) {
    if (!Platform.isWindows || running) return;
    _model = model;
    _navKey = navKey;
    tick();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => tick());
  }

  @visibleForTesting
  Future<void> tick() async {
    final model = _model;
    if (model == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Stale items older than the window are marked seen without firing.
    final floor = now - _missedWindowMs;
    for (final r in model.state.reminders) {
      if (r.when < floor) _fired.add('${r.id}|${r.when}');
    }
    for (final e in model.state.entries) {
      if (e.dueAt != null && e.dueAt! < floor) _fired.add('${e.id}|${e.dueAt}');
    }

    final due = collectDue(
      reminders: model.state.reminders,
      entries: model.state.entries,
      chatNameOf: (id) => model.state.chatById(id)?.name ?? 'TN',
      tr: model.tr,
      now: now,
    );
    for (final d in due) {
      if (!_fired.add(d.key)) continue;
      await deliver(d);
    }
  }

  Future<void> deliver(DueItem d) async {
    final model = _model;
    bool focused = false;
    try {
      focused = await windowManager.isFocused();
    } catch (_) {}

    if (focused && model != null) {
      final ctx = _navKey?.currentContext;
      if (ctx == null || !ctx.mounted) return _toastFallback(d);
      if (Platform.isWindows) {
        // Telegram-style overlay toast in the bottom-right corner.
        unawaited(Sounds.taskDone());
        WinToast.show(
          context: ctx,
          title: d.title,
          body: d.body,
          onTap: () {
            WinToast.dismiss();
            Navigator.of(ctx).push(MaterialPageRoute(
                builder: (_) => ChatScreen(model: model, chatId: d.chatId)));
          },
        );
      } else {
        // In-app banner for other platforms.
        unawaited(Sounds.taskDone());
        showInAppBanner(ctx, model.p, title: d.title, body: d.body,
            onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
                builder: (_) => ChatScreen(model: model, chatId: d.chatId))));
      }
    } else {
      await _toastFallback(d);
    }
  }

  /// Window not visible — system toast carries the alert with its own
  /// default sound, so we never add ours on top of it.
  Future<void> _toastFallback(DueItem d) async {
    await RemindersService.instance.showNow(
      id: stableHash(d.key),
      title: d.title,
      body: d.body,
    );
  }
}
