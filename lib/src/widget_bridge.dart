import 'package:flutter/services.dart';

/// Bridge to the native Android home-screen widget.
class WidgetBridge {
  static const _channel = MethodChannel('tn/widget');

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod('update');
    } catch (_) {
      // Widget not present (tests, other platforms) — ignore.
    }
  }
}
