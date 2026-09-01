import 'package:flutter/services.dart';

/// Bridge to the native Android home-screen widget.
class WidgetBridge {
  static const _channel = MethodChannel('tn/widget');
  static void Function()? _onOpenSettings;
  static void Function(String chatId, String? entryId)? _onOpenChat;
  static void Function()? _onShortcutQuickNote;
  static void Function()? _onShortcutAgenda;

  /// Register a callback invoked when the user taps the gear on the widget.
  static set onOpenSettings(void Function()? cb) {
    _onOpenSettings = cb;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') _onOpenSettings?.call();
      if (call.method == 'openChat') {
        final args = call.arguments;
        if (args is String) {
          _onOpenChat?.call(args, null);
        } else if (args is Map) {
          final m = Map<String, dynamic>.from(args);
          final chatId = m['chatId'] as String? ?? m['chat_id'] as String? ?? '';
          final entryId = m['entryId'] as String? ?? m['entry_id'] as String?;
          if (chatId.isNotEmpty) _onOpenChat?.call(chatId, entryId);
        }
      }
      if (call.method == 'shortcutQuickNote') _onShortcutQuickNote?.call();
      if (call.method == 'shortcutAgenda') _onShortcutAgenda?.call();
      return null;
    });
  }

  /// Register a callback invoked when the user taps a task text in the widget (прямо к сообщению).
  static set onOpenChat(void Function(String chatId, String? entryId)? cb) {
    _onOpenChat = cb;
  }

  static set onShortcutQuickNote(void Function()? cb) {
    _onShortcutQuickNote = cb;
  }

  static set onShortcutAgenda(void Function()? cb) {
    _onShortcutAgenda = cb;
  }

  /// Poll for a pending open-chat request from a cold-start widget tap (прямо к сообщению).
  static Future<Map<String, String?>?> takePendingOpenChat() async {
    try {
      final result = await _channel.invokeMethod('getPendingOpenChat');
      if (result == null) return null;
      if (result is String) return {'chatId': result, 'entryId': null};
      if (result is Map) {
        final m = Map<String, dynamic>.from(result);
        final chatId = m['chatId'] as String? ?? m['chat_id'] as String?;
        final entryId = m['entryId'] as String? ?? m['entry_id'] as String?;
        if (chatId == null || chatId.isEmpty) return null;
        return {'chatId': chatId, 'entryId': entryId};
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Legacy: only chatId (для старых вызовов, если где-то ещё используется).
  static Future<String?> takePendingOpenChatLegacy() async {
    final m = await takePendingOpenChat();
    return m?['chatId'];
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
