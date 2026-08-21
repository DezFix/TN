import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'state.dart';

class BackupService {
  static Future<String> export(AppState state) async {
    final json = state.toJson();
    final name = _fileName();
    try {
      final dir = await _downloadsDir();
      final file = File('${dir.path}/$name');
      await file.writeAsString(json);
      return file.path;
    } catch (_) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(json);
      return file.path;
    }
  }

  static Future<List<File>> listBackups() async {
    final dir = await _downloadsDir();
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json') && e.path.contains('tn-backup'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<void> importFrom(File file, AppState state) async {
    final raw = await file.readAsString();
    state.loadFromJson(raw);
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
    return 'tn-backup-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }
}
