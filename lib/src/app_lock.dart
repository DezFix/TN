import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Typedef matching AppModel.tr so callers can pass it directly.
typedef TrFn = String Function(String, [List<String>?]);

/// Lock methods selectable on the lock settings sub-screen.
enum LockMethod { biometric, pattern, pin }

LockMethod lockMethodFromString(String? s) {
  switch (s) {
    case 'pattern':
      return LockMethod.pattern;
    case 'pin':
      return LockMethod.pin;
    default:
      return LockMethod.biometric;
  }
}

/// Optional app lock. Three methods:
///   - biometric: system fingerprint/face via local_auth
///   - pattern / pin: TN's own in-app input, stored as salted SHA-256 hash
///     (the secret itself never persists).
///
/// After a successful unlock the app stays open for a configurable grace
/// window (immediately | 5 min | 10 min); past that window the gate locks.
class AppLock {
  static const _keyEnabled = 'tn-lock-enabled';
  static const _keyMode = 'tn-lock-mode';
  static const _keySecret = 'tn-lock-secret'; // 'saltHex:sha256Hex'
  static const _keyGrace = 'tn-lock-grace-minutes'; // 0 | 5 | 10

  static final LocalAuthentication _auth = LocalAuthentication();

  /// When the gate was last opened (set by [markUnlocked]).
  static DateTime? _lastUnlock;

  /// Test seam: override "now".
  static DateTime Function() nowFn = DateTime.now;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  // ---- prefs ----

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyEnabled) ?? false;
    } catch (_) {}
    return false;
  }

  /// Only call with true after a full setup flow succeeded — the user must
  /// never be able to enable a lock they cannot pass.
  static Future<void> setEnabled(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, v);
      if (!v) {
        await prefs.remove(_keySecret);
        _lastUnlock = null;
      }
    } catch (_) {}
  }

  static Future<LockMethod> getMethod() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return lockMethodFromString(prefs.getString(_keyMode));
    } catch (_) {}
    return LockMethod.biometric;
  }

  static Future<void> setMethod(LockMethod m) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMode, m.name);
    } catch (_) {}
  }

  /// Grace window minutes: 0 (re-lock immediately), 5 or 10.
  static Future<int> getGraceMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_keyGrace) ?? 0;
      return [0, 5, 10].contains(v) ? v : 0;
    } catch (_) {}
    return 0;
  }

  static Future<void> setGraceMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyGrace, minutes);
    } catch (_) {}
  }

  /// Whether a pattern/PIN secret is configured (non-biometric modes).
  static Future<bool> hasSecret() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_keySecret) ?? '').contains(':');
    } catch (_) {}
    return false;
  }

  // ---- secret hashing ----

  /// `salt:hash` where hash = sha256(salt + code). Split out for tests.
  static String hashSecret(String code, String saltHex) =>
      '$saltHex:${crypto.sha256.convert(utf8.encode('$saltHex$code')).toString()}';

  static bool verifyAgainst(String code, String stored) {
    final i = stored.indexOf(':');
    if (i <= 0) return false;
    return hashSecret(code, stored.substring(0, i)) == stored;
  }

  static String randomSalt() {
    final rnd = Random.secure();
    return List.generate(
        8, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Saves a freshly confirmed PIN/pattern code.
  static Future<void> saveSecret(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySecret, hashSecret(code, randomSalt()));
  }

  /// Checks user input against the stored secret. Pure-ish, tested.
  static Future<bool> verifyCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_keySecret) ?? '';
      return stored.isNotEmpty && verifyAgainst(code, stored);
    } catch (_) {}
    return false;
  }

  // ---- unlocking ----

  static void markUnlocked() => _lastUnlock = nowFn();

  static DateTime? get lastUnlockAt => _lastUnlock;

  static void resetGrace() => _lastUnlock = null;

  /// True while inside the grace window after the last unlock. With grace=0
  /// only an unlock made *this instant* counts (i.e. effectively false).
  static Future<bool> isWithinGrace() async {
    final grace = await getGraceMinutes();
    final at = _lastUnlock;
    if (at == null || grace == 0) return false;
    return nowFn().difference(at).inMinutes < grace;
  }

  /// System biometric sheet (method == biometric).
  static Future<bool> unlockBiometrics(TrFn tr) async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.authenticate(
        localizedReason: tr('lock_title'),
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Cascaded verification used everywhere a lock decision is made:
  ///   1. strict biometrics,
  ///   2. device credential fallback (PIN / pattern / password) — otherwise
  ///      a user whose fingerprint stopped working could NEVER turn the
  ///      lock off again,
  ///   3. if the device has no screen protection at all, verification is
  ///      impossible — allow through rather than brick the app.
  static Future<bool> verifyAny(TrFn tr) async {
    if (!supported) return true;
    final secured = await _auth.isDeviceSupported();
    if (!secured) return true;
    if (await biometricsEnrolled) {
      if (await unlockBiometrics(tr)) return true;
    }
    try {
      return await _auth.authenticate(
        localizedReason: tr('lock_title'),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Whether any biometrics are actually enrolled — used to gray out the
  /// biometric option on devices without them.
  static Future<bool> get biometricsEnrolled async {
    if (!supported) return false;
    try {
      final list = await _auth.getAvailableBiometrics();
      return list.isNotEmpty;
    } catch (_) {}
    return false;
  }
}

/// Wraps [child] behind the lock screen while the app is locked. Honors the
/// re-lock grace window: within it the app opens without prompting; past it
/// (including background time longer than the window) the gate locks again.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child, required this.tr});

  final Widget child;
  final TrFn tr;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool? _enabled; // null = still loading
  bool _open = false;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.isEnabled().then((v) async {
      if (!mounted) return;
      setState(() => _enabled = v);
      await _recompute(scheduleTimer: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _recompute();
  }

  Future<void> _recompute({bool scheduleTimer = true}) async {
    if (_enabled != true || !mounted) return;
    final open = await AppLock.isWithinGrace();
    if (!mounted) return;
    setState(() => _open = open);
    if (scheduleTimer) _armExpiryTimer();
  }

  /// Flips the gate shut the moment the grace window ends.
  Future<void> _armExpiryTimer() async {
    _expiryTimer?.cancel();
    final at = AppLock.lastUnlockAt;
    if (at == null) return;
    final grace = await AppLock.getGraceMinutes();
    if (grace == 0 || !mounted) return;
    final left = Duration(minutes: grace) - AppLock.nowFn().difference(at);
    if (left <= Duration.zero) {
      setState(() => _open = false);
    } else {
      _expiryTimer = Timer(left, () {
        if (mounted) setState(() => _open = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled != true || _open) return widget.child;
    return LockScreen(
      tr: widget.tr,
      onUnlocked: () async {
        if (!mounted) return;
        setState(() => _open = true);
        await _armExpiryTimer();
      },
    );
  }
}

/// Full-screen unlock UI. Picks the input for the configured method:
/// system biometrics sheet, TN's pattern grid or TN's PIN pad.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.tr, required this.onUnlocked});

  final TrFn tr;
  final Future<void> Function() onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  LockMethod? _method;
  bool _busy = false;
  String? _error;
  final List<int> _pattern = <int>[];

  @override
  void initState() {
    super.initState();
    AppLock.getMethod().then((m) async {
      if (!mounted) return;
      setState(() => _method = m);
      if (m == LockMethod.biometric) {
        await _tryBiometrics(auto: true);
      }
    });
  }

  Future<void> _success() async {
    AppLock.markUnlocked();
    await widget.onUnlocked();
  }

  Future<void> _tryBiometrics({bool auto = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppLock.verifyAny(widget.tr);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _success();
    } else if (!auto) {
      setState(() => _error = widget.tr('lock_failed'));
    }
  }

  Future<void> _submitCode(String code) async {
    if (_busy || code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppLock.verifyCode(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _success();
    } else {
      setState(() {
        _pattern.clear();
        _error = widget.tr('lock_wrong');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4EA4F6);
    const bg = Color(0xFF1C232C);
    final method = _method ?? LockMethod.biometric;
    final tr = widget.tr;

    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                      color: Color(0x264EA4F6), shape: BoxShape.circle),
                  child:
                      const Icon(Icons.lock_outline, size: 30, color: accent),
                ),
                const SizedBox(height: 16),
                Text(
                  method == LockMethod.pattern
                      ? tr('lock_draw_unlock')
                      : method == LockMethod.pin
                          ? tr('lock_enter_pin')
                          : tr('lock_title'),
                  style: const TextStyle(fontSize: 14.5, color: Colors.white70),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFFF07575))),
                  ),
                const SizedBox(height: 16),
                switch (method) {
                  LockMethod.pattern => PatternLockView(
                      selectedColor: accent,
                      onCompleted: _submitCode,
                    ),
                  LockMethod.pin => PinPadView(
                      accent: accent,
                      hidden: true,
                      onSubmit: _submitCode,
                    ),
                  LockMethod.biometric => Column(
                      children: [
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          style:
                              FilledButton.styleFrom(backgroundColor: accent),
                          icon: const Icon(Icons.fingerprint, size: 20),
                          label: Text(tr('lock_title')),
                          onPressed:
                              _busy ? null : () => _tryBiometrics(),
                        ),
                        const SizedBox(height: 10),
                        Text('TN',
                            style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 2,
                                color:
                                    Colors.white.withValues(alpha: .35))),
                      ],
                    ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Re-exported small widgets so the settings screen can reuse them in setup
// flows without extra files.

/// 3×3 gesture pattern grid. Reports touched dot indices via [onCompleted].
class PatternLockView extends StatefulWidget {
  const PatternLockView({
    super.key,
    required this.onCompleted,
    this.selectedColor = const Color(0xFF4EA4F6),
    this.dimColor = const Color(0xFF717B85),
  });

  /// Reports the drawn pattern as a dash-joined list of dot indices, e.g.  -4-8.
  final ValueChanged<String> onCompleted;
  final Color selectedColor;
  final Color dimColor;

  @override
  State<PatternLockView> createState() => _PatternLockViewState();
}

class _PatternLockViewState extends State<PatternLockView> {
  final List<int> _hits = <int>[];
  Offset? _pointer;

  static const _side = 240.0;
  static const _radius = 26.0;

  Offset _center(int index) {
    final col = index % 3, row = index ~/ 3;
    const cell = _side / 3;
    return Offset(cell * (col + .5), cell * (row + .5));
  }

  int? _hitTest(Offset localPos) {
    for (var i = 0; i < 9; i++) {
      if ((localPos - _center(i)).distance <= _radius + 6 &&
          !_hits.contains(i)) {
        return i;
      }
    }
    return null;
  }

  void _onUpdate(Offset localPos) {
    final hit = _hitTest(localPos);
    var changed = false;
    while (hit != null) {
      _hits.add(hit);
      changed = true;
      break;
    }
    _pointer = localPos;
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _onUpdate(d.localPosition),
      onPanUpdate: (d) => _onUpdate(d.localPosition),
      onPanEnd: (_) {
        final result = List<int>.of(_hits);
        if (mounted) setState(() {
          _hits.clear();
          _pointer = null;
        });
        if (result.length >= 4) {
        widget.onCompleted(result.join('-'));
      }
      },
      child: CustomPaint(
        size: const Size(_side, _side),
        painter: _PatternPainter(
          hits: _hits,
          pointer: _pointer,
          centerOf: _center,
          radius: _radius,
          selectedColor: widget.selectedColor,
          dimColor: widget.dimColor,
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.hits,
    required this.pointer,
    required this.centerOf,
    required this.radius,
    required this.selectedColor,
    required this.dimColor,
  });

  final List<int> hits;
  final Offset? pointer;
  final Offset Function(int) centerOf;
  final double radius;
  final Color selectedColor;
  final Color dimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2;
    for (var i = 0; i < 9; i++) {
      final c = centerOf(i);
      final active = hits.contains(i);
      dotPaint.color = active ? selectedColor : dimColor.withValues(alpha: .6);
      canvas.drawCircle(c, radius * (active ? .55 : .38), dotPaint);
    }
    if (hits.isNotEmpty) {
      final line = Paint()
        ..color = selectedColor.withValues(alpha: .85)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < hits.length - 1; i++) {
        canvas.drawLine(centerOf(hits[i]), centerOf(hits[i + 1]), line);
      }
      if (pointer != null) {
        canvas.drawLine(centerOf(hits.last), pointer!, line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.hits.length != hits.length ||
      old.pointer != pointer ||
      !identical(old.hits, hits);
}

/// Numeric pad used both for PIN setup and PIN unlock.
class PinPadView extends StatefulWidget {
  const PinPadView({
    super.key,
    required this.onSubmit,
    this.accent = const Color(0xFF4EA4F6),
    this.hidden = false,
    this.title,
  });

  final ValueChanged<String> onSubmit;
  final Color accent;

  /// Mask digits as they are typed (unlock screen); show them during setup.
  final bool hidden;
  final String? title;

  @override
  State<PinPadView> createState() => _PinPadViewState();
}

class _PinPadViewState extends State<PinPadView> {
  String _code = '';

  void _tap(String d) {
    if (_code.length >= 8) return;
    setState(() => _code += d);
  }

  // ignore: unused_element
  void _back() {
    if (_code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  Widget _key(String label, {VoidCallback? onTap, IconData? icon}) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Material(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: SizedBox(
                height: 56,
                child: Center(
                  child: icon != null
                      ? Icon(icon, color: Colors.white70, size: 22)
                      : Text(label,
                          style: const TextStyle(
                              fontSize: 20, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(widget.title!,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
        SizedBox(
          height: 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _code.length; i++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: widget.accent),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 264,
          child: Column(
            children: [
              Row(children: [
                _key('1', onTap: () => _tap('1')),
                _key('2', onTap: () => _tap('2')),
                _key('3', onTap: () => _tap('3')),
              ]),
              Row(children: [
                _key('4', onTap: () => _tap('4')),
                _key('5', onTap: () => _tap('5')),
                _key('6', onTap: () => _tap('6')),
              ]),
              Row(children: [
                _key('7', onTap: () => _tap('7')),
                _key('8', onTap: () => _tap('8')),
                _key('9', onTap: () => _tap('9')),
              ]),
              Row(children: [
                _key('', onTap: _back, icon: Icons.backspace_outlined),
                _key('0', onTap: () => _tap('0')),
                _key('✓',
                    onTap: _code.length >= 4 ? () => widget.onSubmit(_code) : null),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
