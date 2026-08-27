import 'dart:async' show unawaited;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/backup.dart';
import '../src/backup_crypto.dart';
import '../src/cloud.dart';
import '../src/gdrive.dart';
import '../src/i18n.dart';
import '../src/sync.dart';
import '../src/theme.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.model});
  final AppModel model;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  NextcloudClient? _nc;
  bool _ncBusy = false;
  GoogleDriveClient? _gd;
  bool _gdBusy = false;
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _encCtrl = TextEditingController();
  bool _showEnc = false;
  String? _dir;
  int _daysIdx = 0;
  static const _daysValues = [0, 1, 3, 5, 7];
  int _maxIdx = 1;
  static const _maxValues = [1, 3, 5];

  @override
  void initState() {
    super.initState();
    _loadAccount();
    _loadLocalSettings();
  }

  Future<void> _loadLocalSettings() async {
    final d = await BackupService.getDays();
    _dir = await BackupService.chosenDir();
    final enc = await BackupService.getPassword();
    final max = await BackupService.getMaxBackups();
    if (!mounted) return;
    setState(() {
      _daysIdx = _daysValues.indexOf(d < 0 ? 0 : d);
      if (_daysIdx < 0) _daysIdx = 0;
      _maxIdx = _maxValues.indexOf(max);
      if (_maxIdx < 0) _maxIdx = 1;
      _encCtrl.text = enc;
      _showEnc = enc.isNotEmpty;
    });
  }

  String _daysLabel(int idx) {
    const keys = ['bk_manual', 'bk_day1', 'bk_day3', 'bk_day5', 'bk_day7'];
    if (idx < 0 || idx >= keys.length) return '';
    return tr(keys[idx]);
  }

  Future<void> _loadAccount() async {
    final c = await NextcloudClient.loadSaved();
    final g = await GoogleDriveClient.loadSaved();
    if (!mounted) return;
    setState(() {
      _nc = c;
      if (c != null) {
        _serverCtrl.text = c.server;
        _userCtrl.text = c.user;
        _passCtrl.text = c.pass;
      }
      _gd = g;
    });
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _encCtrl.dispose();
    super.dispose();
  }

  String tr(String key, [List<String>? args]) => widget.model.tr(key, args);

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 2500),
      backgroundColor: error ? const Color(0xFF3A2020) : p.bgChat,
    ));
  }

  Palette get p => widget.model.p;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: p.text),
        title: Text(tr('backup_screen_title'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _section(tr('backup_local')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.backup_outlined, size: 18),
                    style: FilledButton.styleFrom(backgroundColor: p.accent),
                    label: Text(tr('backup_export')),
                    onPressed: _exportLocal,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.restore, size: 18, color: p.text),
                    label: Text(tr('backup_import'), style: TextStyle(color: p.text)),
                    onPressed: _importLocal,
                  ),
                ),
                const SizedBox(height: 14),
                Text(tr('bk_encrypt'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: p.textFaint)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _encCtrl,
                        obscureText: !_showEnc,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: TextStyle(color: p.text, fontSize: 13.5),
                        onChanged: (v) {
                          unawaited(BackupService.setPassword(v.trim()));
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: tr('bk_pass_field'),
                          hintStyle: TextStyle(color: p.textFaint, fontSize: 12.5),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _encCtrl.text.isEmpty ? p.divider : p.accent)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: p.accent)),
                          suffixIcon: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(_showEnc ? Icons.visibility_off : Icons.visibility,
                                size: 18, color: p.textFaint),
                            onPressed: () => setState(() => _showEnc = !_showEnc),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(tr('bk_encrypt_hint'),
                    style: TextStyle(fontSize: 11, color: p.textFaint)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.schedule_outlined, size: 16, color: p.accent),
                    ),
                    const SizedBox(width: 10),
                    Text(tr('bk_freq'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: p.text)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(TNRadii.pill)),
                      child: Text(_daysLabel(_daysIdx),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accent)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: p.accent,
                    inactiveTrackColor: p.divider.withValues(alpha: 0.35),
                    thumbColor: p.accent,
                    overlayColor: p.accent.withValues(alpha: 0.14),
                    valueIndicatorColor: p.accent,
                    valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                    showValueIndicator: ShowValueIndicator.always,
                  ),
                  child: Slider(
                    value: _daysIdx.toDouble(),
                    min: 0,
                    max: 4,
                    divisions: 4,
                    label: _daysLabel(_daysIdx),
                    onChanged: (v) => setState(() => _daysIdx = v.round()),
                    onChangeEnd: (v) async => await BackupService.setDays(_daysValues[v.round()]),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.filter_none_rounded, size: 16, color: p.accent),
                    ),
                    const SizedBox(width: 10),
                    Text(tr('bk_max'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: p.text)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: p.bgList, borderRadius: BorderRadius.circular(TNRadii.pill), border: Border.all(color: p.divider.withValues(alpha: 0.5))),
                      child: Text('${_maxValues[_maxIdx]}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSoft)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: p.accent,
                    inactiveTrackColor: p.divider.withValues(alpha: 0.35),
                    thumbColor: p.accent,
                    overlayColor: p.accent.withValues(alpha: 0.14),
                    valueIndicatorColor: p.accent,
                    valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                    showValueIndicator: ShowValueIndicator.always,
                  ),
                  child: Slider(
                    value: _maxIdx.toDouble(),
                    min: 0,
                    max: 2,
                    divisions: 2,
                    label: '${_maxValues[_maxIdx]}',
                    onChanged: (v) => setState(() => _maxIdx = v.round()),
                    onChangeEnd: (v) async => await BackupService.setMaxBackups(_maxValues[v.round()]),
                  ),
                ),
                const SizedBox(height: 4),
                Text(tr('bk_max_hint'),
                    style: TextStyle(fontSize: 11.5, color: p.textFaint)),
                const SizedBox(height: 14),
                Text(tr('bk_folder'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: p.textFaint)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 18, color: p.textSoft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dir ?? tr('bk_folder_default'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.textSoft),
                      ),
                    ),
                    TextButton(
                      onPressed: _pickFolder,
                      child: Text(tr('bk_choose')),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(tr('backup_local_hint'),
                    style: TextStyle(fontSize: 11.5, color: p.textFaint)),
              ],
            ),
          ),

          _section(tr('backup_cloud')),
          _card(
            child: _nc == null ? _nextcloudForm() : _nextcloudConnected(),
          ),
          const SizedBox(height: 8),
          _card(
            child: (_gd == null || !_gd!.isConnected)
                ? _gdriveForm()
                : _gdriveConnected(),
          ),
        ],
      ),
    );
  }

  // ---------------- google drive ----------------

  Widget _gdriveForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.add_to_drive, size: 22, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Google Drive',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _gdBusy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login, size: 18),
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            label: Text(tr('gd_connect')),
            onPressed: _gdBusy ? null : _connectGd,
          ),
        ),
      ],
    );
  }

  Widget _gdriveConnected() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.add_to_drive, size: 22, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Google Drive',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
          IconButton(
            tooltip: tr('backup_disconnect'),
            icon: Icon(Icons.link_off, size: 20, color: p.textSoft),
            onPressed: () async {
              await GoogleDriveClient.forget();
              if (!mounted) return;
              setState(() => _gd = null);
            },
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _gdBusy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            label: Text(tr('backup_upload')),
            onPressed: _gdBusy ? null : _uploadGd,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: Text(tr('backup_restore_last')),
            onPressed: _gdBusy ? null : _restoreGd,
          ),
        ),
      ],
    );
  }

  Future<void> _connectGd() async {
    setState(() => _gdBusy = true);
    var client = _gd ?? GoogleDriveClient();
    final ok = await client.connect();
    if (!mounted) return;
    if (ok) {
      unawaited(SyncService.instance.reloadAccount());
      setState(() {
        _gd = client;
        _gdBusy = false;
      });
      _toast(tr('backup_connected'));
    } else {
      setState(() => _gdBusy = false);
      final err = client.lastError.toLowerCase();
      _toast(
        (err.contains('invalid_client') ||
                err.contains('redirect') ||
                err.contains('access_denied'))
            ? '${tr('gd_failed')} ${tr('gd_hint_desktop')}'
            : tr('gd_failed'),
        error: true,
      );
    }
  }

  Future<void> _uploadGd() async {
    if (_gd == null) return;
    setState(() => _gdBusy = true);
    try {
      final ok = await SyncService.instance.push();
      if (!mounted) return;
      setState(() => _gdBusy = false);
      _toast(ok ? tr('gd_uploaded') : tr('gd_failed'), error: !ok);
    } catch (_) {
      if (!mounted) return;
      setState(() => _gdBusy = false);
      _toast(tr('gd_failed'), error: true);
    }
  }

  Future<void> _restoreGd() async {
    if (_gd == null) return;
    setState(() => _gdBusy = true);
    try {
      final ok = await SyncService.instance.pull();
      if (!ok) throw Exception('pull failed');
      widget.model.tr = makeTranslator(widget.model.state.lang);
      widget.model.refresh();
      if (!mounted) return;
      setState(() => _gdBusy = false);
      _toast(tr('backup_imported'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _gdBusy = false);
      _toast(tr('gd_failed'), error: true);
    }
  }

  // ---------------- local ----------------

  Future<void> _pickFolder() async {
    try {
      final d = await getDirectoryPath();
      if (d != null && d.isNotEmpty) {
        await BackupService.setChosenDir(d);
        if (!mounted) return;
        setState(() => _dir = d);
      }
    } catch (_) {
      if (mounted) _toast(tr('bk_folder_android'));
    }
  }

  Future<void> _exportLocal() async {
    try {
      final path = await BackupService.export(widget.model.state,
          dir: _dir, password: _encCtrl.text.trim());
      if (!mounted) return;
      final name = path.split('/').last.split('\\').last;
      _toast(tr('backup_exported', [name]));
    } catch (_) {
      if (mounted) _toast(tr('backup_error'), error: true);
    }
  }

  /// Dialog asking for the encryption password of an encrypted backup.
  Future<String?> _promptPassword() async {
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

  Future<void> _importLocal() async {
    try {
      const groups = [XTypeGroup(label: 'backup', extensions: ['zip', 'json'])];
      final f = await openFile(acceptedTypeGroups: groups);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      var password = _encCtrl.text.trim().isNotEmpty ? _encCtrl.text.trim() : null;
      if (BackupCrypto.isEncrypted(bytes) && password == null) {
        password = await _promptPassword();
        if (password == null || password.isEmpty) return;
      }
      await BackupService.importFromBytes(bytes, f.name, widget.model.state,
          password: password);
      widget.model.tr = makeTranslator(widget.model.state.lang);
      widget.model.refresh();
      if (!mounted) return;
      _toast(tr('backup_imported'));
      setState(() {});
    } on BackupEncryptedException {
      if (mounted) _toast(tr('bk_wrong_pass'), error: true);
    } catch (_) {
      if (mounted) _toast(tr('backup_error'), error: true);
    }
  }

  // ---------------- nextcloud ----------------

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.textFaint)),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.bgChat,
          borderRadius: BorderRadius.circular(TNRadii.md),
          border: Border.all(color: p.divider.withValues(alpha: p.isDark ? 0.45 : 0.35)),
          boxShadow: p.cardShadow,
        ),
        child: child,
      );

  Widget _nextcloudForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.cloud_outlined, size: 22, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Nextcloud',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ]),
        const SizedBox(height: 10),
        _field(_serverCtrl, tr('backup_nc_server'), 'https://cloud.example.com'),
        const SizedBox(height: 8),
        _field(_userCtrl, tr('backup_nc_user'), 'user'),
        const SizedBox(height: 8),
        _field(_passCtrl, tr('backup_nc_pass'), 'вЂўвЂўвЂўвЂўвЂўвЂўвЂўвЂў', obscure: true),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _ncBusy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link, size: 18),
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            label: Text(tr('backup_connect')),
            onPressed: _ncBusy ? null : _connectNc,
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(color: p.text, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: p.textSoft, fontSize: 12.5),
        hintStyle: TextStyle(color: p.textFaint, fontSize: 12.5),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.accent)),
      ),
    );
  }

  Widget _nextcloudConnected() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.cloud_done_outlined, size: 22, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nextcloud',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                Text('${_nc!.user} В· ${_nc!.server.replaceFirst(RegExp('^https?://'), '')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: p.textSoft)),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('backup_disconnect'),
            icon: Icon(Icons.link_off, size: 20, color: p.textSoft),
            onPressed: () async {
              await NextcloudClient.forget();
              if (!mounted) return;
              setState(() => _nc = null);
            },
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _ncBusy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            label: Text(tr('backup_upload')),
            onPressed: _ncBusy ? null : _uploadNc,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: _ncBusy
                ? const SizedBox(width: 16, height: 16)
                : const Icon(Icons.cloud_download_outlined, size: 18, color: null),
            label: Text(tr('backup_restore_last')),
            onPressed: _ncBusy ? null : _restoreNc,
          ),
        ),
      ],
    );
  }

  Future<void> _connectNc() async {
    FocusScope.of(context).unfocus();
    final server = _serverCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (server.isEmpty || user.isEmpty) {
      _toast(tr('backup_error'), error: true);
      return;
    }
    setState(() => _ncBusy = true);
    final client =
        NextcloudClient(server: server, user: user, pass: pass);
    final ok = await client.testConnection();
    if (!mounted) return;
    if (ok) {
      await client.save();
      setState(() {
        _nc = client;
        _ncBusy = false;
      });
      _toast(tr('backup_connected'));
    } else {
      setState(() => _ncBusy = false);
      _toast(tr('backup_connect_failed'), error: true);
    }
  }

  Future<void> _uploadNc() async {
    if (_nc == null) return;
    setState(() => _ncBusy = true);
    try {
      final zip = await BackupService.payloadForUpload(widget.model.state);
      final name = BackupService.lastExportName();
      final ok = await _nc!.upload(name, zip);
      if (!mounted) return;
      setState(() => _ncBusy = false);
      _toast(ok ? tr('backup_uploaded') : tr('backup_cloud_failed'), error: !ok);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ncBusy = false);
      _toast(tr('backup_cloud_failed'), error: true);
    }
  }

  Future<void> _restoreNc() async {
    if (_nc == null) return;
    setState(() => _ncBusy = true);
    try {
      final list = await _nc!.listBackups();
      if (list.isEmpty) {
        if (!mounted) return;
        setState(() => _ncBusy = false);
        _toast(tr('backup_cloud_empty'), error: true);
        return;
      }
      final bytes = await _nc!.download(list.last);
      if (bytes == null) throw Exception('download failed');
      var password = _encCtrl.text.trim().isNotEmpty ? _encCtrl.text.trim() : null;
      if (BackupCrypto.isEncrypted(bytes) && password == null) {
        password = await _promptPassword();
        if (password == null || password.isEmpty) {
          if (!mounted) return;
          setState(() => _ncBusy = false);
          return;
        }
      }
      await BackupService.importFromBytes(bytes, list.last, widget.model.state,
          password: password);
      widget.model.tr = makeTranslator(widget.model.state.lang);
      widget.model.refresh();
      if (!mounted) return;
      setState(() => _ncBusy = false);
      _toast(tr('backup_imported'));
    } on BackupEncryptedException {
      if (!mounted) return;
      setState(() => _ncBusy = false);
      _toast(tr('bk_wrong_pass'), error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ncBusy = false);
      _toast(tr('backup_cloud_failed'), error: true);
    }
  }
}
