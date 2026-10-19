import 'dart:convert';
import 'dart:io' show File, FileMode, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_log.dart';
import 'i18n.dart';
import 'models.dart';

/// Notification actions: postpone by a day vs mark done.
/// Legacy `tn_snooze_*` ids are still matched below for alarms that were
/// armed before the update (their buttons travel with the payload).
const snoozeActions = [
  ('tn_snooze_10', 10),
  ('tn_snooze_60', 60),
];

/// Silent background actions (no UI): postpone +24h, mark the entry done.
const notifPostponeAction = 'tn_postpone';
const notifDoneAction = 'tn_done';
const _postponeMinutes = 24 * 60;

AndroidNotificationDetails _androidDetails(
    String title, String body, List<String>? actionLabels) {
  final labels = actionLabels ?? const ['Postpone', 'Done'];
  return AndroidNotificationDetails(
    'tn_messages',
    'TN messages',
    channelDescription: 'Messages and reminders like Telegram',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
    styleInformation: MessagingStyleInformation(
      // Chat name plays the "sender" — no hardcoded locale string here.
      Person(name: title),
      conversationTitle: title,
      groupConversation: false,
      messages: [Message(body, DateTime.now(), Person(name: title))],
    ),
    ticker: '$title: $body',
    actions: [
      AndroidNotificationAction(notifPostponeAction, labels[0],
          showsUserInterface: false, cancelNotification: true),
      AndroidNotificationAction(notifDoneAction, labels[1],
          showsUserInterface: false, cancelNotification: true),
    ],
  );
}

/// Background entry point for notification action taps (snooze) while the
/// app process is gone. Edits the shared state JSON directly — the same
/// contract the Kotlin widget uses — bumps the stamp and re-arms the native
/// alarm, so the reminder fires later even if TN is never opened.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse details) async {
  await handleSnoozeResponse(details);
}

/// Marks a todo entry done straight from the notification ("Выполнено").
/// Works headlessly on raw JSON like the widget does; returns true when the
/// entry was found. Custom reminders are dropped instead (nothing to check).
///
/// A recurring entry completed LATE (yesterday's occurrence this morning)
/// also opens the fresh today/next-selected occurrence right away and arms
/// its alarm: waiting for the midnight rollover left the user with no next
/// reminder (and no armed alarm) unless the app was opened that day.
Future<bool> completeEntryFromJson(String id) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return false;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    var hit = false;
    String? freshChatId;
    int? freshWhen;
    String? freshBody;
    final entries = data['entries'] as List?;
    if (entries != null) {
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i] as Map<String, dynamic>;
        if (e['id'] != id) continue;
        final items = e['items'] as List?;
        if (items != null) {
          for (final it in items) {
            (it as Map<String, dynamic>)['done'] = true;
          }
        }
        e['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
        // Overdue occurrence of a recurring task: close it AND open the
        // fresh one (same calendar-day semantics as the midnight rollover),
        // then arm its alarm — "done" must never end the chain.
        final parsed = Entry.fromJson(Map<String, dynamic>.from(e));
        if (rolloverRecurringTasks([parsed], DateTime.now()).isNotEmpty) {
          e['dueAt'] = parsed.dueAt;
          e['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
          final open = <String>[];
          if (items != null) {
            for (final it in items) {
              final m = it as Map<String, dynamic>;
              m['done'] = false;
              final t = (m['text'] as String? ?? '').trim();
              if (t.isNotEmpty) open.add(t);
            }
          }
          freshChatId = parsed.chatId;
          freshWhen = parsed.dueAt;
          freshBody = open.isNotEmpty ? open.join('\n') : parsed.text;
        }
        hit = true;
        break;
      }
    }
    if (!hit) {
      // Custom (non-entry) reminder: "done" just deletes it.
      final reminders = data['reminders'] as List?;
      if (reminders != null) {
        final before = reminders.length;
        reminders.removeWhere((r) => (r as Map<String, dynamic>)['id'] == id);
        hit = reminders.length != before;
      }
    }
    if (!hit) return false;
    await prefs.setString(storageKey, jsonEncode(data));
    await prefs.setInt('tn-state-stamp', DateTime.now().millisecondsSinceEpoch);
    // Drop the armed alarm for this entry (fresh plugin instance — the
    // background isolate shares nothing with the app's one).
    if (Platform.isAndroid) {
      try {
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        await plugin.cancel(id: stableHash(id));
      } catch (_) {}
    }
    if (freshWhen != null) {
      await _armFromJson(
        data,
        id: id,
        when: freshWhen,
        chatId: freshChatId,
        body: freshBody,
      );
    }
    return true;
  } catch (e, st) {
    AppLog.error('notif.done', e, st);
    return false;
  }
}

/// Shared by the background handler and the in-app response listener.
/// [payload] format: `id|whenMillis`.
Future<bool> handleSnoozeResponse(NotificationResponse details) async {
  final actionId = details.actionId ?? '';
  final payload = details.payload ?? '';
  if (actionId == notifDoneAction) {
    if (payload.isEmpty) return false;
    final sep = payload.lastIndexOf('|');
    if (sep <= 0) return false;
    return completeEntryFromJson(payload.substring(0, sep));
  }
  int? minutes;
  if (actionId == notifPostponeAction) {
    minutes = _postponeMinutes;
  } else {
    final match =
        snoozeActions.where((a) => a.$1 == actionId).firstOrNull;
    if (match != null) minutes = match.$2;
  }
  if (minutes == null || payload.isEmpty) return false;
  final sep = payload.lastIndexOf('|');
  if (sep <= 0) return false;
  final id = payload.substring(0, sep);
  final when = int.tryParse(payload.substring(sep + 1));
  if (when == null) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return false;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final target =
        DateTime.now().millisecondsSinceEpoch + minutes * 60 * 1000;
    var hit = false;
    String? hitChatId;
    String? hitText; // open todo items or the entry text, for the re-arm body
    final reminders = data['reminders'] as List?;
    if (reminders != null) {
      for (var i = 0; i < reminders.length; i++) {
        final r = reminders[i] as Map<String, dynamic>;
        if (r['id'] == id && (r['when'] as num?)?.toInt() == when) {
          r['when'] = target;
          hit = true;
          final cid = r['chatId'];
          if (cid is String) hitChatId = cid;
          break;
        }
      }
    }
    if (!hit) {
      final entries = data['entries'] as List?;
      if (entries != null) {
        for (var i = 0; i < entries.length; i++) {
          final e = entries[i] as Map<String, dynamic>;
          if (e['id'] == id &&
              e['dueAt'] != null &&
              (e['dueAt'] as num).toInt() == when) {
            e['dueAt'] = target;
            e['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
            hit = true;
            final cid = e['chatId'];
            if (cid is String) hitChatId = cid;
            final open = <String>[];
            final items = e['items'] as List?;
            if (items != null) {
              for (final it in items) {
                if (it is! Map || it['done'] == true) continue;
                final t = (it['text'] as String? ?? '').trim();
                if (t.isNotEmpty) open.add(t);
              }
            }
            hitText = open.isNotEmpty
                ? open.join('\n')
                : (e['text'] as String? ?? '');
            break;
          }
        }
      }
    }
    if (!hit) return false;
    await prefs.setString(storageKey, jsonEncode(data));
    await prefs.setInt('tn-state-stamp', DateTime.now().millisecondsSinceEpoch);
    await _armFromJson(
      data,
      id: id,
      when: target,
      chatId: hitChatId,
      body: hitText,
    );
    return true;
  } catch (e, st) {
    AppLog.error('snooze.bg', e, st);
    return false;
  }
}

/// (Re)arms the native alarm for [id] at [when] with the content from the
/// state JSON — shared by the postpone shift and the late-completion roll
/// (both run headless in the background isolate, where the app's plugin
/// instance does not exist). Past instants are skipped: the occurrence stays
/// visible as overdue in the app instead.
Future<void> _armFromJson(
  Map<String, dynamic> data, {
  required String id,
  required int when,
  String? chatId,
  String? body,
}) async {
  if (!Platform.isAndroid) return;
  if (when <= DateTime.now().millisecondsSinceEpoch) return;
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    tzdata.initializeTimeZones();
    // Rebuild the real notification content — an empty "TN" toast with
    // no text and no buttons was the old behavior.
    final tr = makeTranslator((data['lang'] as String?) ?? 'ru');
    var title = 'TN';
    final chats = data['chats'] as List?;
    if (chats != null && chatId != null) {
      for (final c in chats) {
        if (c is Map && c['id'] == chatId) {
          final n = c['name'];
          if (n is String && n.isNotEmpty) title = n;
          break;
        }
      }
    }
    final text = (body != null && body.trim().isNotEmpty)
        ? body.trim()
        : tr('remind_body');
    final exact =
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    await plugin.zonedSchedule(
      id: stableHash(id),
      title: title,
      body: text,
      scheduledDate: tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(when, isUtc: true),
        tz.UTC,
      ),
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          title,
          text,
          [tr('notif_postpone'), tr('notif_done')],
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '$id|$when',
    );
  } catch (e, st) {
    AppLog.error('notif.arm', e, st);
  }
}

extension _FirstOf<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class RemindersService {
  static final RemindersService instance = RemindersService._();

  RemindersService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _tzAttempts = 0;
  String _lastError = '';

  /// Set by the app at startup: receives (actionId, payload) taps made while
  /// the app was running, so snooze updates the live model immediately.
  static void Function(String actionId, String payload)? onNotificationAction;

  String get lastError => _lastError;
  bool get ready => _ready;

  void _log(String msg) {
    _lastError = msg;
    assert(() {
      debugPrint('TN reminders: $msg');
      return true;
    }());
    // Best-effort file log — the only way to see what happened on a device
    // we cannot attach a debugger to.
    try {
      getApplicationDocumentsDirectory().then((d) {
        final f = File(
            '${d.path}${Platform.pathSeparator}tn-reminders.log');
        f.writeAsStringSync(
            '${DateTime.now().toIso8601String()} $msg\n',
            mode: FileMode.append);
      }).catchError((_) {});
    } catch (_) {}
  }

  Future<void> init() async {
    try {
      if (!_ready) {
        await _initTz();
        final ok = await _plugin
            .initialize(
              // Branch on Android (not on !Windows): widget tests run on a
              // Windows host but report TargetPlatform.android.
              settings: Platform.isAndroid
                  ? const InitializationSettings(
                      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
                    )
                  : const InitializationSettings(
                      windows: WindowsInitializationSettings(
                        appName: 'TN',
                        appUserModelId: 'app.tn.tn',
                        guid: 'F4A9E2D1-7C3B-4E8A-9D2F-1B6C5A0E9D43',
                      ),
                    ),
              onDidReceiveNotificationResponse: (details) async {
                final actionId = details.actionId ?? '';
                if (actionId.startsWith('tn_snooze_') ||
                    actionId == notifPostponeAction ||
                    actionId == notifDoneAction) {
                  await handleSnoozeResponse(details);
                  onNotificationAction?.call(details.actionId!, details.payload ?? '');
                }
              },
              onDidReceiveBackgroundNotificationResponse:
                  notificationBackgroundHandler,
            )
            .timeout(const Duration(seconds: 4));
        // Native registration can legitimately fail (e.g. the Start Menu
        // AUMID shortcut could not be created on Windows) — never pretend
        // we are ready or every later schedule call will silently throw.
        _ready = ok ?? false;
        _log(_ready ? 'init ok' : 'init failed (plugin returned false)');
      }
    } catch (e) {
      _log('init threw: $e');
    }
  }

  Future<void> _initTz() async {
    if (_tzAttempts > 3) return;
    _tzAttempts++;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone().timeout(const Duration(seconds: 4));
      tz.setLocalLocation(tz.getLocation(name.identifier));
    } catch (_) {
      // timezone registry may be partial on some devices
    }
  }

  Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return; // Windows needs no runtime permission
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      // Only opens the system "Alarms & reminders" page when needed.
      if (await canScheduleExactNotifications()) {
        // already granted
      } else {
        await requestExactAlarmsPermissionPage();
      }
    } catch (_) {}
  }

  Future<bool> canScheduleExactNotifications() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  /// Opens the system "Alarms & reminders" page; returns when user comes back.
  Future<void> requestExactAlarmsPermissionPage() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  Future<bool> requestNotificationsPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// True when the OS lets us schedule exact alarms; otherwise we degrade to
  /// inexact instead of letting zonedSchedule throw and lose the reminder.
  Future<bool> exactAlarmsAllowed() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when the user (or the OS below Android 13) allows showing
  /// notifications at all.
  Future<bool> notificationsAllowed() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> schedule(Reminder r, String title, String body,
      {List<String>? snoozeLabels, List<String>? actionLabels}) async {
    // Desktop: native scheduled toasts proved unreliable (AUMID/shortcut
    // registration, timezone shifts) — ReminderEngine delivers reminders
    // itself with Telegram-style overlays instead.
    if (!Platform.isAndroid) return true;
    if (!_ready) await init();
    try {
      // Absolute instant via UTC — a broken/unknown local timezone can no
      // longer shift the target into the past (which made zonedSchedule
      // throw and silently lose the reminder, seen on Windows).
      final when = tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(r.when, isUtc: true),
        tz.UTC,
      );
      final exact = await exactAlarmsAllowed();
      await _plugin.zonedSchedule(
        id: stableHash(r.id),
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: _androidDetails(title, body, actionLabels ?? snoozeLabels),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: '${r.id}|${r.when}',
      );
      _log('scheduled ${r.id} at $when');
      return true;
    } catch (e) {
      _log('schedule ${r.id} failed: $e');
      return false;
    }
  }

  Future<void> cancel(Reminder r) async {
    try {
      await _plugin.cancel(id: stableHash(r.id));
    } catch (_) {}
  }

  Future<void> cancelById(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  Future<void> showNow({required int id, required String title, required String body}) async {
    if (!_ready) await init();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _androidDetails(title, body, null),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {}
  }
}

@visibleForTesting
FlutterLocalNotificationsPlugin notificationsPluginForTest() =>
    RemindersService.instance._plugin;
