import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../src/app_model.dart';
import '../src/backup.dart';
import '../src/backup_crypto.dart';
import '../src/i18n.dart';
import '../src/reminders.dart';
import '../src/theme.dart';
import 'list_screen.dart';

final _welRecorder = AudioRecorder();

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.model});
  final AppModel model;
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with WidgetsBindingObserver {
  String _lang = 'ru';
  String _theme = 'dark';
  bool _notifOk = false;
  bool _alarmsOk = false;
  bool _micOk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lang = widget.model.state.lang;
    _theme = widget.model.state.theme;
    if (_theme != 'light' && _theme != 'dark') _theme = 'dark';
    _checkPerms();
    _checkMic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _welRecorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system "Alarms & reminders" page.
    if (state == AppLifecycleState.resumed) _checkPerms();
  }

  Future<void> _checkPerms() async {
    final n = await RemindersService.instance.notificationsAllowed();
    final a = await RemindersService.instance.exactAlarmsAllowed();
    if (!mounted) return;
    setState(() {
      _notifOk = n;
      _alarmsOk = a;
    });
  }

  Future<void> _grantNotifications() async {
    await RemindersService.instance.requestNotificationsPermission();
    await _checkPerms();
  }

  Future<void> _grantAlarms() async {
    await RemindersService.instance.requestExactAlarmsPermissionPage();
    await _checkPerms();
  }

  Future<void> _checkMic() async {
    if (!Platform.isAndroid) return;
    bool ok;
    try {
      ok = await _welRecorder.hasPermission();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _micOk = ok);
  }

  Future<void> _grantMic() async {
    await _checkMic();
  }

  Future<void> _finish() async {
    await widget.model.setLang(_lang);
    await widget.model.setTheme(_theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tn-welcome-done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ListScreen(model: widget.model)));
  }

  Future<void> _restoreBackup() async {
    try {
      const groups = [XTypeGroup(label: 'backup', extensions: ['zip', 'json'])];
      final f = await openFile(acceptedTypeGroups: groups);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      String? password;
      if (BackupCrypto.isEncrypted(bytes)) {
        password = await _promptPassword();
        if (password == null || password.isEmpty) return;
      }
      await BackupService.importFromBytes(bytes, f.name, widget.model.state,
          password: password);
      widget.model.tr = makeTranslator(widget.model.state.lang);
      if (!mounted) return;
      setState(() {
        _lang = widget.model.state.lang;
        _theme = widget.model.state.theme;
      });
      await _finish();
    } on BackupEncryptedException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(makeTranslator(_lang)('bk_wrong_pass')),
          backgroundColor: const Color(0xFF3A2020),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(makeTranslator(_lang)('backup_error')),
          backgroundColor: const Color(0xFF3A2020),
        ));
      }
    }
  }

  Future<String?> _promptPassword() async {
    final tr = makeTranslator(_lang);
    final p = paletteFor(_theme);
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(tr('bk_pass_prompt'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(color: p.text, fontSize: 14),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('cancel'), style: TextStyle(color: p.textSoft))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(tr('todo_done')),
          ),
        ],
      ),
    );
    return res?.trim();
  }

  @override
  Widget build(BuildContext context) {
    final tr = makeTranslator(_lang);
    final effective = _theme == 'dark'
        ? 'dark'
        : _theme == 'light'
            ? 'light'
            : (MediaQuery.platformBrightnessOf(context) == Brightness.dark ? 'dark' : 'light');
    final p = paletteFor(effective);

    return Scaffold(
      backgroundColor: p.bgList,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: const Text('TN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
                  ),
                  const SizedBox(width: 12),
                  Text('TN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: p.text, letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: 16),
              Text(tr('welcome_headline'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text, height: 1.2)),
              const SizedBox(height: 10),
              Text(tr('welcome_desc'), style: TextStyle(fontSize: 15, color: p.textSoft, height: 1.45)),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _feat(tr('welcome_feat1'), p),
                    const SizedBox(height: 8),
                    _feat(tr('welcome_feat2'), p),
                    const SizedBox(height: 8),
                    _feat(tr('welcome_feat3'), p),
                    const SizedBox(height: 8),
                    _feat(tr('welcome_feat4'), p),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(tr('welcome_lang'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (code, label) in appLanguages)
                    ChoiceChip(
                      label: Text(label),
                      selected: _lang == code,
                      onSelected: (_) => setState(() => _lang = code),
                      selectedColor: p.accent,
                      backgroundColor: p.bgChat,
                      labelStyle: TextStyle(color: _lang == code ? Colors.white : p.textSoft, fontWeight: FontWeight.w600, fontSize: 13),
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: _lang == code ? p.accent : p.divider)),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(tr('welcome_theme'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in ['light', 'dark'])
                    ChoiceChip(
                      label: Text(tr(t)),
                      selected: _theme == t,
                      onSelected: (_) => setState(() => _theme = t),
                      selectedColor: p.accent,
                      backgroundColor: p.bgChat,
                      labelStyle: TextStyle(color: _theme == t ? Colors.white : p.textSoft, fontWeight: FontWeight.w600, fontSize: 13),
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: _theme == t ? p.accent : p.divider)),
                    ),
                ],
              ),

              // ---- Permissions ----
              const SizedBox(height: 24),
              Text(tr('perm_title'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              _permCard(
                p,
                icon: Icons.notifications_active_outlined,
                title: tr('perm_notifications'),
                desc: tr('perm_notifications_desc'),
                granted: _notifOk,
                grantLabel: tr('perm_grant'),
                onGrant: _grantNotifications,
              ),
              const SizedBox(height: 8),
              _permCard(
                p,
                icon: Icons.alarm_outlined,
                title: tr('perm_alarms'),
                desc: tr('perm_alarms_desc'),
                granted: _alarmsOk,
                grantLabel: tr('perm_grant'),
                onGrant: _grantAlarms,
              ),
              const SizedBox(height: 8),
              _permCard(
                p,
                icon: Icons.mic_none_outlined,
                title: tr('perm_mic'),
                desc: tr('perm_mic_desc'),
                granted: _micOk,
                grantLabel: tr('perm_grant'),
                onGrant: _grantMic,
              ),
              if (!_notifOk || !_alarmsOk) ...[
                const SizedBox(height: 8),
                Text(tr('perm_hint'), style: TextStyle(fontSize: 12, color: p.textFaint, height: 1.4)),
              ],

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _notifOk && _alarmsOk ? p.accent : p.textFaint.withValues(alpha: .35),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: (_notifOk && _alarmsOk) ? _finish : null,
                  child: Text(
                    (_notifOk && _alarmsOk) ? tr('welcome_start') : tr('perm_finish_locked'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _restoreBackup,
                  child: Text(tr('welcome_restore'),
                      style: TextStyle(fontSize: 13, color: p.textSoft)),
                ),
              ),
              const SizedBox(height: 10),
              Center(child: Text('TN · ${tr('chat_subtitle')}', style: TextStyle(fontSize: 11, color: p.textFaint))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feat(String text, Palette p) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.35))),
        ],
      );

  Widget _permCard(
    Palette p, {
    required IconData icon,
    required String title,
    required String desc,
    required bool granted,
    required String grantLabel,
    required VoidCallback onGrant,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.bgChat,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: granted ? p.accent.withValues(alpha: .55) : p.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: granted ? p.accent : p.textSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 11.5, color: p.textSoft, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (granted)
            Icon(Icons.check_circle, color: p.accent, size: 26)
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onGrant,
              child: Text(grantLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
