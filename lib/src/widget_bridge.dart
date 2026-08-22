import 'package:flutter/services.dart';

/// Bridge to the native Android home-screen widget.
class WidgetBridge {
  static const _channel = MethodChannel('tn/widget');
  static void Function()? _onOpenSettings;

  /// Register a callback invoked when the user taps the gear on the widget.
  static set onOpenSettings(void Function()? cb) {
    _onOpenSettings = cb;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') _onOpenSettings?.call();
      return null;
    });
  }

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod('update');
    } catch (_) {
      // Widget not present (tests, other platforms) — ignore.
    }
  }
}
