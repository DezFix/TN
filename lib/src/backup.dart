import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media.dart';
import 'state.dart';

/// App settings carried inside every backup zip (chats live in data.json,
/// theme/lang are part of it too; these are extra UI preferences).
const backupPrefKeys = [
  'tn-widget-alpha',
  'tn-widget-font',
  'tn-daywidget-period',
];

class BackupService {
  // ---- local backup settings ----
  static const freqKey = 'tn-backup-freq'; // legacy: manual | daily | weekly
  static const daysKey = 'tn-backup-days'; // 0=manual, else every N days
  static const dirKey = 'tn-backup-dir';
  static const lastKey = 'tn-backup-last';
  static const allowedDays = [0, 1, 3, 5, 7];

  static Future<String> getFrequency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(freqKey) ?? 'manual';
    } catch (_) {}
    return 'manual';
  }

  /// 0 = manual, otherwise back up every N days (slider position).
  static Future<int> getDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(daysKey);
      if (v != null && allowedDays.contains(v)) return v;
      final s = prefs.getString(freqKey); // migrate old chip values
      if (s == 'daily') return 1;
      if (s == 'weekly') return 7;
    } catch (_) {}
    return 0;
  }

  static Future<void> setDays(int d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(daysKey, allowedDays.contains(d) ? d : 0);
    } catch (_) {}
  }

  static Future<void> setFrequency(String v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(freqKey, v);
    } catch (_) {}
  }

  static Future<String?> chosenDir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(dirKey);
    } catch (_) {}
    return null;
  }

  static Future<void> setChosenDir(String? v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (v == null || v.isEmpty) {
        await prefs.remove(dirKey);
      } else {
        await prefs.setString(dirKey, v);
      }
    } catch (_) {}
  }

  /// Runs the scheduled backup when due. Returns the written file path or
  /// null (manual mode / no folder chosen / not yet due).
  static Future<String?> maybeAutoBackup(AppState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final days = await getDays();
      if (days <= 0) return null;
      final dir = prefs.getString(dirKey);
      if (dir == null || dir.isEmpty) return null;
      final last = prefs.getInt(lastKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < days * 24 * 3600 * 1000) return null;
      final path = await export(state, dir: dir);
      await prefs.setInt(lastKey, DateTime.now().millisecondsSinceEpoch);
      return path;
    } catch (_) {}
    return null;
  }

  /// Build the zip and write it silently to [dir] (or Downloads). No share
  /// sheet — "back up now" should just save the file.
  static Future<String> export(AppState state, {String? dir}) async {
    final name = _fileName();
    final zip = await _buildZip(state);
    Directory target = await _downloadsDir();
    if (dir != null && dir.isNotEmpty) {
      final d = Directory(dir);
      if (await d.exists()) target = d;
    }
    final file = File('${target.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(zip, flush: true);
    return file.path;
  }

  static Future<List<int>> buildZip(AppState state) => _buildZip(state);

  static Future<List<int>> _buildZip(AppState state) async {
    final archive = Archive();
    final jsonBytes = utf8.encode(state.toJson());
    archive.add(ArchiveFile.bytes('data.json', jsonBytes));
    try {
      final prefs = await SharedPreferences.getInstance();
      final snap = <String, Object?>{};
      for (final k in backupPrefKeys) {
        final v = prefs.get(k);
        if (v != null) snap[k] = v;
      }
      if (snap.isNotEmpty) {
        archive.add(ArchiveFile.bytes('prefs.json', utf8.encode(jsonEncode(snap))));
      }
    } catch (_) {}
    try {
      final mediaDir = await MediaStore().dir();
      if (await mediaDir.exists()) {
        await for (final e in mediaDir.list()) {
          if (e is! File) continue;
          try {
            final base = e.uri.pathSegments.last;
            final bytes = await e.readAsBytes();
            archive.add(ArchiveFile.bytes('media/$base', bytes));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return ZipEncoder().encode(archive);
  }

  static Future<List<File>> listBackups() async {
    final dirs = <Directory>[
      Directory('/storage/emulated/0/Download'),
      await getApplicationDocumentsDirectory(),
    ];
    final files = <File>[];
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final p = e.path;
        if ((p.endsWith('.zip') || p.endsWith('.json')) &&
            p.contains('tn-backup')) {
          files.add(e);
        }
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<void> importFrom(File file, AppState state) async {
    final bytes = await file.readAsBytes();
    await importFromBytes(bytes, file.path, state);
  }

  /// Accepts raw bytes of a .zip (or legacy .json) backup — used by cloud
  /// restore where there is no local file yet.
  static Future<void> importFromBytes(
      List<int> bytes, String sourceName, AppState state) async {
    if (sourceName.toLowerCase().endsWith('.zip')) {
      await _importZipBytes(bytes, state);
    } else {
      state.loadFromJson(utf8.decode(bytes));
      await state.save();
    }
  }

  static Future<void> _importZipBytes(List<int> bytes, AppState state) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? data;
    ArchiveFile? prefsFile;
    for (final f in archive) {
      if (f.name == 'data.json' || f.name.endsWith('/data.json')) data = f;
      if (f.name == 'prefs.json' || f.name.endsWith('/prefs.json')) {
        prefsFile = f;
      }
    }
    if (data == null) throw const FormatException('no data.json in backup');
    state.loadFromJson(utf8.decode(data.content));

    // apply saved app settings
    if (prefsFile != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final snap = jsonDecode(utf8.decode(prefsFile.content)) as Map<String, dynamic>;
        for (final e in snap.entries) {
          if (!backupPrefKeys.contains(e.key)) continue;
          final v = e.value;
          if (v is int) {
            await prefs.setInt(e.key, v);
          } else if (v is double) {
            await prefs.setDouble(e.key, v);
          } else if (v is String) {
            await prefs.setString(e.key, v);
          } else if (v is bool) {
            await prefs.setBool(e.key, v);
          }
        }
      } catch (_) {}
    }

    // restore media files that are missing locally
    final mediaDir = await MediaStore().dir();
    for (final f in archive) {
      if (!f.isFile) continue;
      final parts = f.name.split('/');
      if (parts.length != 2 || parts.first != 'media') continue;
      final dest =
          File('${mediaDir.path}${Platform.pathSeparator}${parts.last}');
      if (await dest.exists()) continue;
      await dest.writeAsBytes(f.content, flush: true);
    }
    await state.save();
  }

  /// Filename the next export will use (also used for cloud uploads).
  static String lastExportName() => _fileName();

  static Future<Directory> _downloadsDir() async {
    if (Platform.isAndroid) {
      try {
        final dl = Directory('/storage/emulated/0/Download');
        if (await dl.exists()) return dl;
      } catch (_) {}
    }
    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) return dl;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  static String _fileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'tn-backup-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }
}
