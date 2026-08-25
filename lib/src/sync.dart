import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_model.dart';
import 'backup.dart';
import 'gdrive.dart';
import 'i18n.dart';
import 'models.dart';
import 'state.dart';

/// Google Drive sync between devices (phone <-> PC).
///
/// Strategy:
///   - A single fixed file `tn_backup.zip` on Drive (no accumulation).
///   - On startup: compare Drive's `modifiedTime` with a local stamp; download
///     only when the cloud copy is newer, push when local is newer.
///   - When BOTH sides changed since last sync, a per-entry merge is performed:
///     each entry's `updatedAt` field decides which version wins.
///
/// Media files referenced by entries are included inside the zip (same as the
/// local backup format) so no separate media sync is needed.
class SyncService {
  static final SyncService instance = SyncService._();

  SyncService._();

  static const _syncFileName = 'tn_backup.zip';
  static const _prefFileId = 'tn-sync-file-id';
  static const _prefLastSync = 'tn-sync-last-sync';

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

  Future<void> reloadAccount() async {
    try {
      _gd = await GoogleDriveClient.loadSaved();
    } catch (_) {}
  }

  void notifyChanged() {
    if (!enabled || _busy) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 30), push);
  }

  /// Push local state to Drive (overwrite the fixed file).
  Future<bool> push() async {
    final m = _model, gd = _gd;
    if (m == null || gd == null || !gd.isConnected || _busy) return false;
    _busy = true;
    try {
      final zip = await BackupService.buildZip(m.state);
      final prefs = await SharedPreferences.getInstance();
      var fileId = prefs.getString(_prefFileId);

      bool ok;
      if (fileId != null) {
        // Update existing file.
        ok = await gd.updateFile(fileId, _syncFileName, zip);
        if (!ok) {
          // File might have been deleted on Drive — recreate.
          ok = await gd.upload(_syncFileName, zip);
          if (ok) {
            final info = await gd.findFile(_syncFileName);
            if (info != null) fileId = info['id'] as String?;
          }
        }
      } else {
        // First push — create the file.
        ok = await gd.upload(_syncFileName, zip);
        if (ok) {
          final info = await gd.findFile(_syncFileName);
          if (info != null) fileId = info['id'] as String?;
        }
      }

      if (ok && fileId != null) {
        await prefs.setString(_prefFileId, fileId);
        await prefs.setInt(_prefLastSync, DateTime.now().millisecondsSinceEpoch);
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Startup reconciliation.
  ///
  /// Returns what happened: 'restored', 'pushed', 'merged', 'fresh' (nothing
  /// to do), or 'off' (not connected).
  Future<String> syncOnStart() async {
    final m = _model, gd = _gd;
    if (m == null || gd == null || !gd.isConnected) return 'off';
    try {
      final prefs = await SharedPreferences.getInstance();
      final localSyncTs = prefs.getInt(_prefLastSync) ?? 0;

      // Find or create the fixed file on Drive.
      var fileId = prefs.getString(_prefFileId);
      Map<String, dynamic>? remoteInfo;
      if (fileId != null) {
        // Verify the file still exists.
        remoteInfo = await gd.findFile(_syncFileName);
        if (remoteInfo == null) {
          // File was deleted on Drive — just push local.
          await prefs.remove(_prefFileId);
          return await push() ? 'pushed' : 'off';
        }
        fileId = remoteInfo['id'] as String?;
      } else {
        remoteInfo = await gd.findFile(_syncFileName);
        if (remoteInfo != null) {
          fileId = remoteInfo['id'] as String?;
          await prefs.setString(_prefFileId, fileId!);
        }
      }

      // No remote file at all → push local.
      if (fileId == null || remoteInfo == null) {
        return await push() ? 'pushed' : 'off';
      }

      // Parse Drive's modifiedTime (ISO 8601).
      final remoteModStr = remoteInfo['modifiedTime'] as String?;
      final remoteModMs = remoteModStr != null
          ? DateTime.tryParse(remoteModStr)?.millisecondsSinceEpoch ?? 0
          : 0;

      final remoteIsNewer = remoteModMs > localSyncTs;
      final localIsNewer = localSyncMs(m) > localSyncTs;

      if (!remoteIsNewer && !localIsNewer) {
        // Neither side changed since last sync.
        return 'fresh';
      }

      if (remoteIsNewer && !localIsNewer) {
        // Only remote changed — restore it.
        final bytes = await gd.download(fileId);
        if (bytes == null || bytes.isEmpty) return 'off';
        await BackupService.importFromBytes(bytes, _syncFileName, m.state);
        m.tr = makeTranslator(m.state.lang);
        m.refresh();
        await prefs.setInt(_prefLastSync, DateTime.now().millisecondsSinceEpoch);
        debugPrint('TN sync: restored from Drive');
        return 'restored';
      }

      if (!remoteIsNewer && localIsNewer) {
        // Only local changed — push.
        return await push() ? 'pushed' : 'off';
      }

      // BOTH changed — per-entry merge.
      final bytes = await gd.download(fileId);
      if (bytes == null || bytes.isEmpty) return await push() ? 'pushed' : 'off';

      // Parse remote state.
      final remoteState = AppState();
      try {
        await BackupService.importFromBytes(bytes, _syncFileName, remoteState);
      } catch (_) {
        return await push() ? 'pushed' : 'off';
      }

      _mergeStates(m.state, remoteState);
      m.tr = makeTranslator(m.state.lang);
      m.refresh();
      await m.save();
      await push(); // push merged result back
      await prefs.setInt(_prefLastSync, DateTime.now().millisecondsSinceEpoch);
      debugPrint('TN sync: merged local + remote');
      return 'merged';
    } catch (_) {
      return 'off';
    }
  }

  /// Per-entry merge: for every entry id present in either state, keep the
  /// version with the newer `updatedAt`.  Chats, folders, and reminders are
  /// merged by id as well (newest wins).
  void _mergeStates(AppState local, AppState remote) {
    // --- entries ---
    final localById = <String, Entry>{for (final e in local.entries) e.id: e};
    for (final re in remote.entries) {
      final le = localById[re.id];
      if (le == null) {
        // Entry exists only on remote — add it.
        local.entries.add(re);
      } else if (re.updatedAt > le.updatedAt) {
        // Remote is newer — replace.
        local.entries.removeWhere((e) => e.id == re.id);
        local.entries.add(re);
      }
      // else local is newer or equal — keep local (no-op).
    }

    // --- chats ---
    final localChats = <String, Chat>{for (final c in local.chats) c.id: c};
    for (final rc in remote.chats) {
      if (!localChats.containsKey(rc.id)) {
        local.chats.add(rc);
      }
    }

    // --- folders ---
    final localFolders = <String, Folder>{for (final f in local.folders) f.id: f};
    for (final rf in remote.folders) {
      if (!localFolders.containsKey(rf.id)) {
        local.folders.add(rf);
      }
    }

    // --- reminders ---
    final localRems = <String, Reminder>{for (final r in local.reminders) r.id: r};
    for (final rr in remote.reminders) {
      if (!localRems.containsKey(rr.id)) {
        local.reminders.add(rr);
      }
    }
  }

  /// Max entry timestamp across all entries — used for legacy comparison.
  int localSyncMs(AppModel m) {
    var ts = 0;
    for (final e in m.state.entries) {
      if (e.updatedAt > ts) ts = e.updatedAt;
    }
    return ts;
  }

  static Future<int?> lastPush() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_prefLastSync);
  }
}
