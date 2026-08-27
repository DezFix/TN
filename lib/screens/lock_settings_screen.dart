import 'package:flutter/material.dart';

import '../src/app_lock.dart';
import '../src/app_model.dart';
import '../src/theme.dart';

/// Lock sub-screen: method (biometrics / pattern / PIN) and the re-lock
/// grace window (immediately / 5 min / 10 min).
class LockSettingsScreen extends StatefulWidget {
  const LockSettingsScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<LockSettingsScreen> createState() => _LockSettingsScreenState();
}

class _LockSettingsScreenState extends State<LockSettingsScreen> {
  bool _enabled = false;
  bool _busy = false;
  Set<LockMethod> _methods = {};
  int _grace = 0;
  bool _biometricsOk = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final en = await AppLock.isEnabled();
    final m = await AppLock.getEnabledMethods();
    final g = await AppLock.getGraceMinutes();
    final bio = await AppLock.biometricsEnrolled;
    if (!mounted) return;
    setState(() {
      _enabled = en;
      _methods = m;
      _grace = g;
      _biometricsOk = bio;
    });
  }

  String tr(String key, [List<String>? args]) => widget.model.tr(key, args);
  Palette get p => widget.model.p;

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: p.bgChat));
  }

  // ---- enabling flows ----

  /// Disabling requires passing the CURRENT lock once — otherwise anyone
  /// with a moment of access could just turn protection off.
  Future<void> _disable() async {
    final ok = await _verifyCurrent();
    if (!ok) return;
    await AppLock.setEnabled(false);
    if (!mounted) return;
    setState(() {
      _enabled = false;
      _methods = {};
    });
  }

  Future<bool> _verifyCurrent() async {
    // Try whichever method is currently active.
    if (_methods.contains(LockMethod.biometric) && _biometricsOk) {
      return AppLock.verifyAny(widget.model.tr);
    }
    // For code methods, prompt for the one that's set.
    if (_methods.contains(LockMethod.pattern)) {
      final code = await _promptCode(
        title: tr('lock_draw_unlock'),
        pinMode: false,
      );
      if (code == null) return false;
      return AppLock.verifyCode(code, LockMethod.pattern);
    }
    if (_methods.contains(LockMethod.pin)) {
      final code = await _promptCode(
        title: tr('lock_enter_pin'),
        pinMode: true,
      );
      if (code == null) return false;
      return AppLock.verifyCode(code, LockMethod.pin);
    }
    return false;
  }

  Future<void> _enableWithBiometrics() async {
    setState(() => _busy = true);
    final ok = await AppLock.verifyAny(widget.model.tr);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    _methods.add(LockMethod.biometric);
    await AppLock.setEnabledMethods(_methods);
    await AppLock.setEnabled(true);
    await _load();
    _toast(tr('lock_saved'));
  }

  /// Setup flow: enter → confirm. Persists only when both inputs match.
  Future<void> _setupCode(LockMethod method) async {
    final isPin = method == LockMethod.pin;
    final first = await _promptCode(
      title: isPin ? tr('lock_set_pin') : tr('lock_draw_pattern'),
      pinMode: isPin,
    );
    if (first == null) return;
    var second = await _promptCode(
      title: isPin ? tr('lock_confirm_pin') : tr('lock_confirm_pattern'),
      pinMode: isPin,
    );
    // One retry on mismatch — enough friction, no dead end.
    while (second != null && second != first) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('lock_mismatch')),
          backgroundColor: p.bgChat,
        ));
      }
      second = await _promptCode(
        title: isPin ? tr('lock_confirm_pin') : tr('lock_confirm_pattern'),
        pinMode: isPin,
        );
    }
    if (second == null) return;

    await AppLock.saveSecret(first, method);
    _methods.add(method);
    await AppLock.setEnabledMethods(_methods);
    await AppLock.setEnabled(true);
    await _load();
    if (mounted) _toast(tr('lock_saved'));
  }

  /// Full-screen input sheet. Returns the entered code, or null when the
  /// sheet was dismissed / validation rejected it.
  Future<String?> _promptCode({
    required String title,
    required bool pinMode,
  }) async {
    String? result;
    final error = ValueNotifier<String?>(null);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.modalBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: p.divider, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: p.text)),
            ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (ctx, err, _) {
                if (err == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child:
                      Text(err, style: TextStyle(fontSize: 12, color: p.danger)),
                );
              },
            ),
            const SizedBox(height: 10),
            SafeArea(
              child: pinMode
                  ? PinPadView(
                      accent: p.accent,
                      onSubmit: (code) {
                        if (code.length < 4 || code.length > 8) {
                          error.value = tr('lock_mismatch');
                          return;
                        }
                        result = code;
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    )
                  : PatternLockView(
                      selectedColor: p.accent,
                      onCompleted: (pattern) {
                        result = pattern;
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    error.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(tr('lock_menu'),
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 6),
          // Master switch
          _card(
            child: InkWell(
              onTap: _busy ? null : () async {
                if (_enabled) {
                  await _disable();
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Icon(Icons.fingerprint,
                      size: 24, color: _enabled ? p.accent : p.textSoft),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('lock_menu'),
                            style:
                                TextStyle(fontSize: 14.5, color: p.text)),
                        Text(tr('lock_hint'),
                            style: TextStyle(
                                fontSize: 11, color: p.textFaint)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    activeColor: p.accent,
                    onChanged: _busy
                        ? null
                        : (v) async {
                            if (v == _enabled) return;
                            if (v) {
                              await _enableFirstAvailable();
                            } else {
                              await _disable();
                            }
                          },
                  ),
                ],
              ),
            ),
          ),

          _section(tr('lock_methods')),
          _methodToggle(
            selected: _methods.contains(LockMethod.biometric),
            icon: Icons.fingerprint,
            title: tr('lock_method_biometric'),
            subtitle: _biometricsOk
                ? tr('lock_method_biometric_sub')
                : tr('lock_failed'),
            enabled: _biometricsOk,
            onTap: () => _toggleMethod(LockMethod.biometric),
          ),
          _methodToggle(
            selected: _methods.contains(LockMethod.pattern),
            icon: Icons.gesture,
            title: tr('lock_method_pattern'),
            subtitle: tr('lock_method_pattern_sub'),
            onTap: () => _toggleMethod(LockMethod.pattern),
          ),
          _methodToggle(
            selected: _methods.contains(LockMethod.pin),
            icon: Icons.dialpad,
            title: tr('lock_method_pin'),
            subtitle: tr('lock_method_pin_sub'),
            onTap: () => _toggleMethod(LockMethod.pin),
          ),

          _section(tr('lock_relock')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('lock_relock_hint'),
                    style: TextStyle(fontSize: 11.5, color: p.textFaint)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (v, key) in [
                      (0, 'lock_relock_now'),
                      (5, 'lock_relock_5'),
                      (10, 'lock_relock_10')
                    ]) ...[
                      Expanded(
                        child: _graceChip(v, tr(key)),
                      ),
                      if (v != 10) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }


  /// Called by the master switch when turning ON — picks the first available
  /// method and runs its setup.
  Future<void> _enableFirstAvailable() async {
    if (_biometricsOk) {
      await _enableWithBiometrics();
    } else {
      await _setupCode(LockMethod.pin);
    }
  }

  /// Toggle a method on/off. When enabling, runs setup. When disabling,
  /// ensures at least one other method stays on.
  Future<void> _toggleMethod(LockMethod m) async {
    if (_busy) return;

    if (_methods.contains(m)) {
      // Turning off — ensure at least one method remains.
      if (_methods.length <= 1) {
        _toast(tr('lock_last_method'));
        return;
      }
      _methods.remove(m);
      if (m == LockMethod.pin || m == LockMethod.pattern) {
        await AppLock.clearSecret(m);
      }
      await AppLock.setEnabledMethods(_methods);
      await _load();
    } else {
      // Turning on — run setup flow.
      switch (m) {
        case LockMethod.biometric:
          await _enableWithBiometrics();
          break;
        case LockMethod.pin:
        case LockMethod.pattern:
          await _setupCode(m);
          break;
      }
    }
  }

  Future<void> _setGrace(int v) async {
    await AppLock.setGraceMinutes(v);
    if (!mounted) return;
    setState(() => _grace = v);
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: p.textFaint)),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: p.bgChat, borderRadius: BorderRadius.circular(12)),
        child: child,
      );

  Widget _methodToggle({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool enabled = true,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: p.bgChat,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? p.accent : Colors.transparent, width: 1.5),
        ),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          enabled: enabled && !_busy,
          leading: Icon(icon, color: selected ? p.accent : p.textSoft),
          title: Text(title,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: enabled ? p.text : p.textFaint)),
          subtitle: Text(subtitle,
              style: TextStyle(fontSize: 11.5, color: p.textFaint)),
          trailing: Icon(
            selected ? Icons.check_box : Icons.check_box_outline_blank,
            size: 22,
            color: selected ? p.accent : p.textFaint,
          ),
          onTap: onTap,
        ),
      );

  Widget _graceChip(int value, String label) {
    final selected = _grace == value;
    return InkWell(
      onTap: () => _setGrace(value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: .16) : p.bgList,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? p.accent : p.divider, width: 1.5),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? p.accent : p.textSoft)),
      ),
    );
  }
}
