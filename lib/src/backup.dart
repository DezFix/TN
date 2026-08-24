import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'media.dart';
import 'state.dart';

class BackupService {
  /// Build a zip containing the full state JSON plus every media file
  /// referenced by entries. Writes it to Downloads when possible (so the
  /// in-app import list can find it), then opens the share sheet so the
  /// user can also send it anywhere (Drive, Telegram, Files...).
  static Future<String> export(AppState state) async {
    final name = _fileName();
    final zip = await _buildZip(state);
    File file;
    try {
      final dir = await _downloadsDir();
      file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(zip, flush: true);
    } catch (_) {
      final dir = await getApplicationDocumentsDirectory();
      file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(zip, flush: true);
    }
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/zip', name: name)],
        subject: name,
      );
    } catch (_) {}
    return file.path;
  }

  static Future<List<int>> _buildZip(AppState state) async {
    final archive = Archive();
    final jsonBytes = utf8.encode(state.toJson());
    archive.add(ArchiveFile.bytes('data.json', jsonBytes));
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
    if (file.path.toLowerCase().endsWith('.zip')) {
      await _importZip(file, state);
    } else {
      final raw = await file.readAsString();
      state.loadFromJson(raw);
      await state.save();
    }
  }

  static Future<void> _importZip(File file, AppState state) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? data;
    for (final f in archive) {
      if (f.name == 'data.json' || f.name.endsWith('/data.json')) data = f;
    }
    if (data == null) throw const FormatException('no data.json in backup');
    state.loadFromJson(utf8.decode(data.content));

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

  static Future<Directory> _downloadsDir() async {
    try {
      // Android often /storage/emulated/0/Download
      final dl = Directory('/storage/emulated/0/Download');
      if (await dl.exists()) return dl;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  static String _fileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'tn-backup-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }
}
