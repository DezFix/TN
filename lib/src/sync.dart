import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_model.dart';
import 'backup.dart';
import 'gdrive.dart';
import 'i18n.dart';

/// Lightweight Google Drive sync between devices (phone <-> PC).
///
/// - After any change a full backup is pushed ~30 seconds later (debounced).
/// - On startup the newest auto backup is compared with local data: newer
///   cloud state is restored, otherwise the local state is pushed up.
///
/// Auto backups use the name `tn-backup-auto-<millis>.zip`; manual backups
/// are never touched. Last-write-wins, guarded by entry timestamps.
class SyncService {
  static final SyncService instance = SyncService._();

  SyncService._();

  static const _autoPrefix = 'tn-backup-auto-';
  static const _keepAutos = 3;

  AppModel? _model;
  GoogleDriveClient? _gd;
  Timer? _debounce;
  bool _busy = false;
  bool _bound = false;

  bool get enabled => _gd?.isConnected ?? false;

  Future<void> bind(AppModel model) async {
    if (_bound) return;
    _bound = true;
    _model = model;
    try {
      _gd = await GoogleDriveClient.loadSaved();
    } catch (_) {}
  }

  /// Re-reads stored credentials (after connect/disconnect in backup screen).
  Future<void> reloadAccount() async {
    try {
      _gd = await GoogleDriveClient.loadSaved();
    } catch (_) {}
  }

  /// Called on every model change — pushes debounced.
  void notifyChanged() {
    if (!enabled || _busy) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 30), push);
  }

  int localTs(AppModel m) {
    var ts = 0;
    for (final e in m.state.entries) {
      if (e.ts > ts) ts = e.ts;
    }
    return ts;
  }

  Future<bool> push() async {
    final m = _model, gd = _gd;
    if (m == null || gd == null || !gd.isConnected || _busy) return false;
    _busy = true;
    try {
      final zip = await BackupService.buildZip(m.state);
      final name =
          '$_autoPrefix${DateTime.now().millisecondsSinceEpoch}.zip';
      final ok = await gd.upload(name, zip);
      if (ok) unawaited(_pruneOldAutos(gd));
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<void> _pruneOldAutos(GoogleDriveClient gd) async {
    try {
      final autos = (await gd.listBackups())
          .where((e) => e.key.startsWith(_autoPrefix))
          .toList(); // oldest first
      for (final old in autos.take(autos.length - _keepAutos)) {
        await gd.delete(old.value);
      }
    } catch (_) {}
  }

  /// Startup reconciliation. Returns what happened ('restored', 'pushed',
  /// 'fresh' — nothing to do, 'off' — not connected / failed).
  Future<String> syncOnStart() async {
    final m = _model, gd = _gd;
    if (m == null || gd == null || !gd.isConnected) return 'off';
    try {
      final list = await gd.listBackups();
      final autos =
          list.where((e) => e.key.startsWith(_autoPrefix)).toList();
      if (autos.isEmpty && list.isEmpty) return await push() ? 'pushed' : 'off';

      final latest = (autos.isNotEmpty ? autos : list).last;
      final digits = latest.key
          .replaceAll(_autoPrefix, '')
          .replaceAll(RegExp(r'[^0-9]'), '');
      final remoteMs = int.tryParse(digits) ?? 0;
      final local = localTs(m);

      if (local >= remoteMs) {
        // Local is at least as new — refresh the cloud copy when it differs.
        if (autos.isEmpty || local > remoteMs) {
          return await push() ? 'pushed' : 'off';
        }
        return 'fresh';
      }

      // Cloud is newer — restore it before the UI settles on stale data.
      final bytes = await gd.download(latest.value);
      if (bytes == null || bytes.isEmpty) return 'off';
      await BackupService.importFromBytes(bytes, latest.key, m.state);
      m.tr = makeTranslator(m.state.lang);
      m.refresh();
      debugPrint('TN sync: restored ${latest.key}');
      return 'restored';
    } catch (_) {
      return 'off';
    }
  }

  /// Test helper: last stored sync prefs key (kept for future diagnostics).
  static Future<int?> lastPush() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('tn-sync-last-push');
  }
}
