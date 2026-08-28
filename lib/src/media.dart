import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'models.dart';

/// Top-level function for [compute]: decode, resize, and JPEG-encode an image
/// off the main thread so the UI stays responsive during send.
Uint8List _processImage(Uint8List args) {
  final bytes = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes; // fallback: return original
  var image = decoded;
  const maxDim = 1600;
  if (image.width > maxDim || image.height > maxDim) {
    image = img.copyResize(image,
        width: image.width > maxDim ? maxDim : null,
        height: image.height > maxDim ? maxDim : null,
        interpolation: img.Interpolation.cubic);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 82));
}

class MediaStore {
  Directory? _dir;

  Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}${Platform.pathSeparator}$mediaDirName');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    return _dir!;
  }

  Future<String> saveImage(String sourcePath, {int maxDim = 1600, int quality = 82}) async {
    final d = await dir();
    final name = '${uid('img')}.jpg';
    final dest = '${d.path}${Platform.pathSeparator}$name';

    // Read bytes on main thread (fast I/O), then decode+resize in an isolate.
    final bytes = await File(sourcePath).readAsBytes();
    final processed = await compute(_processImage, bytes);
    await File(dest).writeAsBytes(processed);
    return name;
  }

  /// Quick copy without resize — lets the entry appear in chat instantly.
  /// The caller then fires [optimizeImage] in the background to downscale.
  Future<String> quickCopy(String sourcePath) async {
    final d = await dir();
    final name = '${uid('img')}.jpg';
    await File(sourcePath).copy('${d.path}${Platform.pathSeparator}$name');
    return name;
  }

  /// Downscale an already-copied image in a background isolate (fire-and-forget).
  Future<void> optimizeImage(String mediaName, {int maxDim = 1600, int quality = 82}) async {
    try {
      final d = await dir();
      final dest = '${d.path}${Platform.pathSeparator}$mediaName';
      final bytes = await File(dest).readAsBytes();
      final processed = await compute(_processImage, bytes);
      await File(dest).writeAsBytes(processed);
    } catch (_) {}
  }

  Future<String> saveFile(String sourcePath, String prefix) async {
    final d = await dir();
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : '';
    final name = ext.isEmpty ? uid(prefix) : '${uid(prefix)}.$ext';
    await File(sourcePath).copy('${d.path}${Platform.pathSeparator}$name');
    return name;
  }

  Future<String> pathOf(String mediaName) async {
    final d = await dir();
    return '${d.path}${Platform.pathSeparator}$mediaName';
  }

  Future<void> remove(String? mediaName) async {
    if (mediaName == null || mediaName.isEmpty) return;
    try {
      final f = File(await pathOf(mediaName));
      if (await f.exists()) await f.delete();
    } catch (e, st) {
      AppLog.error('media.remove', e, st);
    }
  }

  Directory? _trashDir;

  /// `tn_media/_trash` — deleted files rest here so an Undo can bring them
  /// back; purged by [purgeTrash] on the next launches.
  Future<Directory> trashDir() async {
    if (_trashDir != null) return _trashDir!;
    final base = await dir();
    _trashDir = Directory('${base.path}${Platform.pathSeparator}_trash');
    if (!await _trashDir!.exists()) await _trashDir!.create(recursive: true);
    return _trashDir!;
  }

  /// Move a media file into the trash folder instead of deleting it.
  /// Forwarded copies SHARE the same media name, so a hard delete would
  /// break every other entry pointing at the file.
  Future<bool> softRemove(String? mediaName) async {
    if (mediaName == null || mediaName.isEmpty) return false;
    try {
      final f = File(await pathOf(mediaName));
      if (!await f.exists()) return false;
      final t = await trashDir();
      final dest = File(
          '${t.path}${Platform.pathSeparator}$mediaName');
      if (await dest.exists()) await dest.delete();
      await f.rename(dest.path);
      return true;
    } catch (e, st) {
      AppLog.error('media.softRemove', e, st);
      return false;
    }
  }

  /// Put a soft-removed file back.
  Future<void> restore(String? mediaName) async {
    if (mediaName == null || mediaName.isEmpty) return;
    try {
      final t = await trashDir();
      final src = File('${t.path}${Platform.pathSeparator}$mediaName');
      if (!await src.exists()) return;
      final dest = File(await pathOf(mediaName));
      if (await dest.exists()) return; // someone else already owns the slot
      await src.rename(dest.path);
    } catch (e, st) {
      AppLog.error('media.restore', e, st);
    }
  }

  /// Drop trashed media older than [maxAge] (default 48 h).
  Future<int> purgeTrash({Duration maxAge = const Duration(hours: 48)}) async {
    var removed = 0;
    try {
      final t = await trashDir();
      if (!await t.exists()) return 0;
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final e in t.list()) {
        if (e is! File) continue;
        try {
          if (await e.lastModified().then((m) => m.isBefore(cutoff))) {
            await e.delete();
            removed++;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return removed;
  }

  /// Copy-on-forward: duplicated entries must not share one media file,
  /// otherwise deleting either copy destroys both.
  Future<String?> copyMedia(String mediaName) async {
    try {
      final src = File(await pathOf(mediaName));
      if (!await src.exists()) return null;
      final dot = mediaName.lastIndexOf('.');
      final ext = dot >= 0 ? mediaName.substring(dot) : '';
      final newName = '${uid('m')}$ext';
      final d = await dir();
      await src.copy('${d.path}${Platform.pathSeparator}$newName');
      return newName;
    } catch (e, st) {
      AppLog.error('media.copyMedia', e, st);
      return null;
    }
  }

  // ---- cache weight helpers (for Settings) ----

  Future<int> _dirBytes(Directory d) async {
    var total = 0;
    try {
      if (!await d.exists()) return 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Bytes in the main media dir (without _trash) — фото/голос/файлы.
  Future<int> mediaBytes() async {
    final d = await dir();
    var total = await _dirBytes(d);
    // _dirBytes includes _trash, subtract it to keep them separate
    try {
      final t = await trashDir();
      total -= await _dirBytes(t);
      if (total < 0) total = 0;
    } catch (_) {}
    return total;
  }

  /// Bytes in _trash — мусор который ещё можно отменить, но уже жрёт место.
  Future<int> trashBytes() async => _dirBytes(await trashDir());

  /// Bytes in temp (tn-update.apk + system cache). The downloaded APK alone
  /// is ~68 MB, so users see where the "мусор" comes from.
  Future<int> tempBytes() async {
    try {
      final tmp = await getTemporaryDirectory();
      return _dirBytes(tmp);
    } catch (_) {
      return 0;
    }
  }

  /// Total cache + trash + temp for the Settings header.
  Future<({int media, int trash, int temp, int total})> cacheStats() async {
    final m = await mediaBytes();
    final tr = await trashBytes();
    final tm = await tempBytes();
    return (media: m, trash: tr, temp: tm, total: m + tr + tm);
  }

  /// Wipe only trash + temp (safe: не трогает актуальную медиа).
  Future<int> clearTrashAndTemp() async {
    var cleared = 0;
    cleared += await purgeTrash(maxAge: Duration.zero);
    // extra pass: any file in _trash regardless of age
    try {
      final t = await trashDir();
      if (await t.exists()) {
        await for (final e in t.list()) {
          if (e is File) {
            try {
              await e.delete();
              cleared++;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    try {
      final tmp = await getTemporaryDirectory();
      if (await tmp.exists()) {
        await for (final e in tmp.list()) {
          if (e is File) {
            try {
              final n = e.path.toLowerCase();
              if (n.endsWith('.apk') || n.contains('tn-update')) {
                await e.delete();
                cleared++;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return cleared;
  }
}

String humanSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 100) return mb.toStringAsFixed(0);
  return mb.toStringAsFixed(1);
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  final mb = bytes / (1024 * 1024);
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}