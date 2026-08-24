import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/backup.dart';
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

  @override
  void initState() {
    super.initState();
    _loadAccount();
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
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.upload, size: 18),
                    style: FilledButton.styleFrom(backgroundColor: p.accent),
                    label: Text(tr('backup_export')),
                    onPressed: _exportLocal,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.download, size: 18, color: p.text),
                    label: Text(tr('backup_import'), style: TextStyle(color: p.text)),
                    onPressed: _importLocal,
                  ),
                ),
                const SizedBox(height: 8),
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
      final zip = await BackupService.buildZip(widget.model.state);
      final name = BackupService.lastExportName();
      final ok = await _gd!.upload(name, zip);
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
      final list = await _gd!.listBackups();
      if (list.isEmpty) {
        if (!mounted) return;
        setState(() => _gdBusy = false);
        _toast(tr('gd_empty'), error: true);
        return;
      }
      final bytes = await _gd!.download(list.last.key);
      if (bytes == null) throw Exception('download failed');
      await BackupService.importFromBytes(bytes, list.last.value, widget.model.state);
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

  Future<void> _exportLocal() async {
    try {
      await BackupService.export(widget.model.state);
      if (!mounted) return;
      _toast(tr('backup_shared'));
    } catch (_) {
      if (mounted) _toast(tr('backup_error'), error: true);
    }
  }

  Future<void> _importLocal() async {
    final files = await BackupService.listBackups();
    if (!mounted) return;
    if (files.isEmpty) {
      _toast(tr('backup_error'), error: true);
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: p.modalBg,
        title: Text(tr('backup_import'), style: TextStyle(color: p.text)),
        children: [
          for (final f in files.take(20))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f.path),
              child: Text(f.path.split('/').last.split('\\').last,
                  style: TextStyle(color: p.text, fontSize: 13)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('close'), style: TextStyle(color: p.textSoft)),
          ),
        ],
      ),
    );
    if (picked == null) return;
    try {
      await BackupService.importFrom(File(picked), widget.model.state);
      widget.model.tr = makeTranslator(widget.model.state.lang);
      widget.model.refresh();
      if (!mounted) return;
      _toast(tr('backup_imported'));
      setState(() {});
    } catch (_) {
      if (mounted) _toast(tr('backup_error'), error: true);
    }
  }

  // ---------------- nextcloud ----------------

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
        child: Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: p.textFaint)),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.bgChat,
          borderRadius: BorderRadius.circular(14),
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
        _field(_passCtrl, tr('backup_nc_pass'), '••••••••', obscure: true),
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
                Text('${_nc!.user} · ${_nc!.server.replaceFirst(RegExp('^https?://'), '')}',
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
      final zip = await BackupService.buildZip(widget.model.state);
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
      await BackupService.importFromBytes(bytes, list.last, widget.model.state);
      widget.model.tr = makeTranslator(widget.model.state.lang);
      widget.model.refresh();
      if (!mounted) return;
      setState(() => _ncBusy = false);
      _toast(tr('backup_imported'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _ncBusy = false);
      _toast(tr('backup_cloud_failed'), error: true);
    }
  }
}
