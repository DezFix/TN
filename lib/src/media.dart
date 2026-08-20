import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

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

    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      var image = decoded;
      if (image.width > maxDim || image.height > maxDim) {
        image = img.copyResize(image,
            width: image.width > maxDim ? maxDim : null,
            height: image.height > maxDim ? maxDim : null,
            interpolation: img.Interpolation.cubic);
      }
      await File(dest).writeAsBytes(img.encodeJpg(image, quality: quality));
    } else {
      await File(sourcePath).copy(dest);
    }
    return name;
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
    } catch (_) {}
  }
}

String humanSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 100) return mb.toStringAsFixed(0);
  return mb.toStringAsFixed(1);
}