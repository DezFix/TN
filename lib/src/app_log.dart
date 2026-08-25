import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Best-effort app log: debugPrint in debug builds plus an append-only
/// `tn-app.log` next to the reminders log. Empty `catch (_) {}` blocks were
/// silently eating disk/network failures — now critical paths call [logError]
/// so problems are at least diagnosable from a device.
class AppLog {
  static bool _failed = false;

  static void _write(String line) {
    if (_failed) return;
    try {
      getApplicationDocumentsDirectory().then((d) {
        final f = File(
            '${d.path}${Platform.pathSeparator}tn-app.log');
        // Keep the file bounded: rotate when it grows past ~256 KB.
        try {
          if (f.lengthSync() > 256 * 1024) f.deleteSync();
        } catch (_) {}
        f.writeAsStringSync(line, mode: FileMode.append);
      }).catchError((_) {
        _failed = true;
      });
    } catch (_) {
      _failed = true;
    }
  }

  static void error(String tag, Object e, [StackTrace? st]) {
    assert(() {
      debugPrint('TN error [$tag]: $e');
      return true;
    }());
    _write('${DateTime.now().toIso8601String()} ERROR [$tag] $e\n');
  }

  static void info(String tag, String msg) {
    assert(() {
      debugPrint('TN [$tag]: $msg');
      return true;
    }());
    _write('${DateTime.now().toIso8601String()} INFO [$tag] $msg\n');
  }
}
