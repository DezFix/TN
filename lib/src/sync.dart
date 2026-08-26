import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'app_model.dart';
import 'backup.dart';
import 'backup_crypto.dart';
import 'gdrive.dart';

/// Google Drive / WebDAV backup sync. Upload is manual (button press).
/// Download MERGES by `updatedAt` instead of replacing local state —
/// pulling an older backup can no longer wipe recent notes.
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  static const _syncFileName = 'tn_backup.zip';
  static const _prefFileId = 'tn-sync-file-id';

  AppModel? _model;
  GoogleDriveClient? _gd;
  bool _bound = false;

  bool get enabled => _gd?.isConnected ?? false;

  Future<void> bind(AppModel model) async {
    if (_bound) return;
    _bound = true;
    _model = model;
    try {
      _gd = await GoogleDriveClient.loadSaved();
    } catch (e, st) {
      AppLog.error('sync.bind', e, st);
    }
  }

  Future<void> reloadAccount() async {
    try {
      _gd = await GoogleDriveClient.loadSaved();
    } catch (_) {}
  }

  /// Upload local state to Drive, overwriting the fixed file. The payload is
  /// E2E-encrypted when a backup password is set.
  Future<bool> push() async {
    final m = _model, gd = _gd;
    if (m == null || gd == null || !gd.isConnected) return false;
    try {
      final zip = await BackupService.payloadForUpload(m.state);
      final prefs = await SharedPreferences.getInstance();
      var fileId = prefs.getString(_prefFileId);

      bool ok;
      if (fileId != null) {
        ok = await gd.updateFile(fileId, _syncFileName, zip);
        if (!ok) {
          ok = await gd.upload(_syncFileName, zip);
          if (ok) {
            final info = await gd.findFile(_syncFileName);
            if (info != null) fileId = info['id'] as String?;
          }
        }
      } else {
        ok = await gd.upload(_syncFileName, zip);
        if (ok) {
          final info = await gd.findFile(_syncFileName);
          if (info != null) fileId = info['id'] as String?;
        }
      }

      if (ok && fileId != null) {
        await prefs.setString(_prefFileId, fileId);
      }
      return ok;
    } catch (e, st) {
      AppLog.error('sync.push', e, st);
      return false;
    }
  }

  /// Download the backup from Drive and merge it into local state.
  Future<bool> pull() async {
    final m = _model, gd = _gd;
    if (m == null || gd == null || !gd.isConnected) return false;
    try {
      final info = await gd.findFile(_syncFileName);
      if (info == null) return false;
      final fileId = info['id'] as String?;
      if (fileId == null) return false;

      final bytes = await gd.download(fileId);
      if (bytes == null || bytes.isEmpty) return false;

      // E2E: decrypt with the stored backup password before parsing.
      var payload = bytes;
      if (BackupCrypto.isEncrypted(bytes)) {
        final password = await BackupService.getPassword();
        if (password.isEmpty) {
          AppLog.info('sync.pull', 'backup is encrypted but no password stored');
          return false;
        }
        final plain = await BackupCrypto.decrypt(bytes, password);
        if (plain == null) {
          AppLog.info('sync.pull', 'decrypt failed (wrong password?)');
          return false;
        }
        payload = plain;
      }

      // Extract data.json and merge record-by-record (LWW on updatedAt).
      final archive = ZipDecoder().decodeBytes(payload);
      ArchiveFile? data;
      for (final f in archive) {
        if (f.name == 'data.json' || f.name.endsWith('/data.json')) {
          data = f;
          break;
        }
      }
      if (data == null) return false;
      m.state.mergeFromJson(utf8.decode(data.content));
      await m.save();
      m.refresh();
      return true;
    } catch (e, st) {
      AppLog.error('sync.pull', e, st);
      return false;
    }
  }
}
