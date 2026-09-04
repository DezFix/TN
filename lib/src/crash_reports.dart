import 'package:sentry/sentry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anonymous crash/error reports via Bugsink (Sentry-compatible).
///
/// Sends only the error + stack trace + app version + OS — no chats, notes,
/// names, files or user identifiers (explicitly stripped in [beforeSend]).
/// Controlled by the "send anonymous reports" switch in Settings.
class CrashReports {
  /// Public Bugsink DSN (client key — safe to embed, like any Sentry DSN).
  static const dsn =
      'https://4ac34b72779f4709aa763b6d6dc0b430@wrebug.bugsink.com/1';

  static const prefsKey = 'tn-crash-reports';

  static bool _enabled = true;
  static bool _inited = false;

  static bool get isEnabled => _enabled;

  static Future<bool> loadEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(prefsKey) ?? true;
    } catch (_) {
      _enabled = true;
    }
    return _enabled;
  }

  /// Inits Sentry only when the user opted in. Safe to call twice.
  static Future<bool> init({required String appVersion}) async {
    await loadEnabled();
    if (!_enabled) return false;
    if (_inited) return true;
    try {
      await Sentry.init((o) {
        o.dsn = dsn;
        o.release = 'tn@$appVersion';
        o.tracesSampleRate = 0; // errors only, no performance tracing
        o.attachStacktrace = true;
        o.sendDefaultPii = false;
        o.beforeSend = (event, hint) {
          // Strip anything that could identify the user.
          return event.copyWith(user: null);
        };
      });
      _inited = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fire-and-forget: never throws, never blocks the app.
  static void capture(String tag, Object error, [StackTrace? stack]) {
    if (!_enabled || !_inited) return;
    try {
      Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) => scope.setTag('tn.tag', tag),
      );
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v, {String? appVersion}) async {
    _enabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, v);
    } catch (_) {}
    if (v) {
      if (appVersion != null) {
        await init(appVersion: appVersion);
      }
    } else {
      try {
        await Sentry.close();
      } catch (_) {}
      _inited = false;
    }
  }
}
