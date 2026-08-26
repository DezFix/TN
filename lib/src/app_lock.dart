import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Typedef matching AppModel.tr so callers can pass it directly.
typedef TrFn = String Function(String, [List<String>?]);

/// Optional app lock (Android/iOS): fingerprint / face / device PIN before
/// the UI is reachable. The gate wraps MaterialApp.builder so every route is
/// covered. On platforms without local_auth support the lock silently stays
/// off — it must never brick the app.
class AppLock {
  static const _key = 'tn-lock-enabled';
  static final LocalAuthentication _auth = LocalAuthentication();

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {}
    return false;
  }

  /// Only call with true after [unlock] succeeded once from the settings
  /// screen — otherwise the user could lock themselves out.
  static Future<void> setEnabled(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, v);
    } catch (_) {}
  }

  static Future<bool> get _deviceCapable async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {}
    return false;
  }

  /// Shows the system auth sheet. Returns true when unlocked.
  static Future<bool> unlock(TrFn tr) async {
    try {
      if (!await _deviceCapable) return true; // nothing to verify against
      return await _auth.authenticate(
        localizedReason: tr('lock_title'),
        options: const AuthenticationOptions(
          biometricOnly: false, // allow the device PIN as fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Wraps [child] behind a lock screen while the app is locked. Re-locks
/// whenever the app leaves foreground.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child, required this.tr});

  final Widget child;
  final TrFn tr;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool? _enabled; // null = still loading
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.isEnabled().then((v) {
      if (!mounted) return;
      setState(() => _enabled = v);
      if (v && !_unlocked) _promptUnlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from background always re-locks (if enabled).
    if (state == AppLifecycleState.paused && _enabled == true) {
      setState(() => _unlocked = false);
    }
  }

  Future<void> _promptUnlock() async {
    final ok = await AppLock.unlock(widget.tr);
    if (!mounted || !ok) return; // user cancelled — button stays available
    setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled != true || _unlocked) return widget.child;
    return _LockScreen(tr: widget.tr, onUnlock: _promptUnlock);
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.tr, required this.onUnlock});

  final TrFn tr;
  final Future<void> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    // The palette is not reachable without the model — use the dark one,
    // which matches the launch/splash look on both platforms.
    const accent = Color(0xFF4EA4F6);
    const bg = Color(0xFF1C232C);
    return ColoredBox(
      color: bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration:
                  const BoxDecoration(color: Color(0x264EA4F6), shape: BoxShape.circle),
              child: const Icon(Icons.lock_outline, size: 34, color: accent),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent),
              icon: const Icon(Icons.fingerprint, size: 20),
              label: Text(tr('lock_title')),
              onPressed: () => onUnlock(),
            ),
            const SizedBox(height: 10),
            Text('TN',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: Colors.white.withValues(alpha: .35))),
          ],
        ),
      ),
    );
  }
}
