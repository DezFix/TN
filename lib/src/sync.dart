import 'package:shared_preferences/shared_preferences.dart';

import 'app_model.dart';
import 'backup.dart';
import 'gdrive.dart';

/// Simple Google Drive backup: a single `tn_backup.zip` file.
/// Upload is manual (button press). Download replaces local state wholesale.
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
    } catch (_) {}
  }

  Future<void> reloadAccount() async {
    try {
      _gd = await GoogleDriveClient.loadSaved();
    } catch (_) {}
  }

  /// Upload local state to Drive, overwriting the fixed file.
  Future<bool> push() async {
    final m = _model, gd = _gd;
    if (m == null || gd == null || !gd.isConnected) return false;
    try {
      final zip = await BackupService.buildZip(m.state);
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
    } catch (_) {
      return false;
    }
  }

  /// Download the backup from Drive and replace local state wholesale.
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
      await BackupService.importFromBytes(bytes, _syncFileName, m.state);
      m.refresh();
      return true;
    } catch (_) {
      return false;
    }
  }
}
