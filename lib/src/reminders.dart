import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class RemindersService {
  static final RemindersService instance = RemindersService._();

  RemindersService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _tzAttempts = 0;

  Future<void> init() async {
    try {
      if (!_ready) {
        await _initTz();
        await _plugin
            .initialize(
              settings: const InitializationSettings(
                android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              ),
            )
            .timeout(const Duration(seconds: 4));
        _ready = true;
      }
    } catch (_) {}
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
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  Future<void> schedule(Reminder r, String title, String body) async {
    if (!_ready) await init();
    try {
      final when = tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(r.when),
        tz.local,
      );
      await _plugin.zonedSchedule(
        id: r.id.hashCode,
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {}
  }

  Future<void> cancel(Reminder r) async {
    try {
      await _plugin.cancel(id: r.id.hashCode);
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