import 'package:flutter/services.dart';

/// Bridge to the native Android home-screen widget.
class WidgetBridge {
  static const _channel = MethodChannel('tn/widget');
  static void Function()? _onOpenSettings;
  static void Function(String chatId)? _onOpenChat;

  /// Register a callback invoked when the user taps the gear on the widget.
  static set onOpenSettings(void Function()? cb) {
    _onOpenSettings = cb;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') _onOpenSettings?.call();
      if (call.method == 'openChat') {
        _onOpenChat?.call(call.arguments as String);
      }
      return null;
    });
  }

  /// Register a callback invoked when the user taps a task text in the widget.
  static set onOpenChat(void Function(String chatId)? cb) {
    _onOpenChat = cb;
  }

  /// Poll for a pending open-chat request from a cold-start widget tap.
  static Future<String?> takePendingOpenChat() async {
    try {
      final result = await _channel.invokeMethod('getPendingOpenChat');
      return result as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod('update');
    } catch (_) {
      // Widget not present (tests, other platforms) — ignore.
    }
  }
}
