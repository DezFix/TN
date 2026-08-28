import 'package:flutter/services.dart';

/// Bridge to the native Android home-screen widget.
class WidgetBridge {
  static const _channel = MethodChannel('tn/widget');
  static void Function()? _onOpenSettings;
  static void Function(String chatId)? _onOpenChat;
  static void Function()? _onHotAdd;
  static void Function()? _onShortcutQuickNote;
  static void Function()? _onShortcutAgenda;

  /// Register a callback invoked when the user taps the gear on the widget.
  static set onOpenSettings(void Function()? cb) {
    _onOpenSettings = cb;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') _onOpenSettings?.call();
      if (call.method == 'openChat') {
        _onOpenChat?.call(call.arguments as String);
      }
      if (call.method == 'hotAdd') _onHotAdd?.call();
      if (call.method == 'shortcutQuickNote') _onShortcutQuickNote?.call();
      if (call.method == 'shortcutAgenda') _onShortcutAgenda?.call();
      return null;
    });
  }

  /// Register a callback invoked when the user taps a task text in the widget.
  static set onOpenChat(void Function(String chatId)? cb) {
    _onOpenChat = cb;
  }

  static set onHotAdd(void Function()? cb) {
    _onHotAdd = cb;
  }

  static set onShortcutQuickNote(void Function()? cb) {
    _onShortcutQuickNote = cb;
  }

  static set onShortcutAgenda(void Function()? cb) {
    _onShortcutAgenda = cb;
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

  static Future<bool> takePendingHotAdd() async {
    try {
      final result = await _channel.invokeMethod('getPendingHotAdd');
      return result as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> takePendingShortcut() async {
    try {
      final result = await _channel.invokeMethod('getPendingShortcut');
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
