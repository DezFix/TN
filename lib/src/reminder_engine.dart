import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_model.dart';
import 'banner.dart';
import 'models.dart';
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
/// Trashed chats never fire.
@visibleForTesting
List<DueItem> collectDue({
  required List<Reminder> reminders,
  required List<Entry> entries,
  required bool Function(String chatId) chatTrashed,
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
    if (chatTrashed(r.chatId)) continue;
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
    if (chatTrashed(e.chatId)) continue;
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
/// every few seconds; due items become our own overlay toast (bottom-right,
/// with sound and snooze buttons) — system notifications are NOT used on
/// Windows anymore, TN draws its own like Telegram does.
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
      chatTrashed: (id) => model.state.chatById(id)?.isTrashed ?? true,
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
    if (model == null) return;
    unawaited(Sounds.taskDone());

    if (Platform.isWindows) {
      // Make sure the window is visible: an overlay inside a hidden-to-tray
      // window would never be seen. Restore it, then drop the Telegram-style
      // toast into the corner.
      try {
        if (!await windowManager.isVisible()) await windowManager.show();
      } catch (_) {}
      final ctx = _navKey?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      WinToast.show(
        context: ctx,
        title: d.title,
        body: d.body,
        actions: [
          ('${d.key}|10', model.tr('snooze_10m')),
          ('${d.key}|60', model.tr('snooze_1h')),
        ],
        onAction: (actionKey) {
          final parts = actionKey.split('|');
          final minutes = int.tryParse(parts.last);
          if (parts.length == 2 && minutes != null) {
            // key format here is `<dueKey>|<minutes>`; rebuild the due key.
            final dueKey =
                parts.sublist(0, parts.length - 1).join('|');
            model.snoozeByKey(dueKey, minutes);
          }
        },
        onTap: () {
          WinToast.dismiss();
          _openChat(d.chatId);
        },
      );
      return;
    }

    // In-app banner for other desktop platforms.
    final ctx = _navKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showInAppBanner(ctx, model.p,
        title: d.title, body: d.body,
        onTap: () => _openChat(d.chatId));
  }

  void _openChat(String chatId) {
    final model = _model;
    if (model == null) return;
    final ctx = _navKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => ChatScreen(model: model, chatId: chatId)));
  }
}
