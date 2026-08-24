import 'dart:io' show File, FileMode, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class RemindersService {
  static final RemindersService instance = RemindersService._();

  RemindersService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _tzAttempts = 0;
  String _lastError = '';

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
            )
            .timeout(const Duration(seconds: 4));
        // Native registration can legitimately fail (e.g. the Start Menu
        // AUMID shortcut could not be created on Windows) — never pretend
        // we are ready or every later schedule call will silently throw.
        _ready = ok ?? false;
        if (!_ready) {
          _log('init failed (plugin returned false)');
        } else {
          _log('init ok');
        }
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

  Future<bool> schedule(Reminder r, String title, String body) async {
    // Desktop: native scheduled toasts proved unreliable (AUMID/shortcut
    // registration, timezone shifts) — ReminderEngine delivers reminders
    // itself with banners and instant toasts instead.
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
          android: AndroidNotificationDetails(
            'tn_messages',
            'TN messages',
            channelDescription: 'Messages and reminders like Telegram',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            styleInformation: MessagingStyleInformation(
              const Person(name: 'Вы'),
              conversationTitle: title,
              groupConversation: false,
              messages: [Message(body, DateTime.now(), Person(name: title))],
            ),
            ticker: '$title: $body',
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      _log('scheduled ${r.id} at $when');
      return true;
    } catch (e) {
      _log('schedule ${r.id} failed: $e');
      return false;
    }
  }

  Future<void> cancel(Reminder r) async {    try {
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
          android: AndroidNotificationDetails(
            'tn_messages',
            'TN messages',
            channelDescription: 'Messages and reminders like Telegram',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            styleInformation: MessagingStyleInformation(
              const Person(name: 'Вы'),
              conversationTitle: title,
              groupConversation: false,
              messages: [Message(body, DateTime.now(), Person(name: title))],
            ),
            ticker: '$title: $body',
          ),
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