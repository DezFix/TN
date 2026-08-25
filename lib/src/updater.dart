import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class Updater {
  static const _channel = MethodChannel('tn/install');

  /// Downloads an APK from [url] to the cache directory, then triggers the
  /// Android package installer via a platform channel.
  /// Returns the path of the downloaded file, or null on error.
  static Future<String?> downloadAndInstall(
    String url,
    void Function(double progress)? onProgress,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}tn-update.apk');

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      if (response.statusCode != 200) return null;

      final total = response.contentLength ?? 0;
      int received = 0;
      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();

      await _channel.invokeMethod('installApk', file.path);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
