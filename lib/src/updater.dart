import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class Updater {
  static const _channel = MethodChannel('tn/install');

  /// Downloads an APK from [url] to the cache directory, then triggers the
  /// Android package installer via a platform channel.
  /// [expectedSha256] (hex, from the GitHub release asset digest) is verified
  /// before anything is handed to the package installer — the old magic-bytes
  /// check only proved the payload was *a* zip, not *our* APK.
  /// Returns the path of the downloaded file, or null on error.
  static Future<String?> downloadAndInstall(
    String url,
    void Function(double progress)? onProgress, {
    String? expectedSha256,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}tn-update.apk');

      // Follow redirects manually — http.Client().send() does NOT follow
      // them, and GitHub's download URLs redirect to their CDN.
      String currentUrl = url;
      List<int>? bytes;
      const maxRedirects = 10;
      for (var i = 0; i < maxRedirects; i++) {
        final req = http.Request('GET', Uri.parse(currentUrl));
        final resp = await http.Client().send(req);

        if (resp.statusCode >= 300 && resp.statusCode < 400) {
          final location = resp.headers['location'];
          if (location == null || location.isEmpty) return null;
          currentUrl = location;
          continue;
        }

        if (resp.statusCode != 200) return null;

        // Stream the body with progress reporting.
        final total = resp.contentLength ?? 0;
        int received = 0;
        final chunks = <int>[];
        await for (final chunk in resp.stream) {
          chunks.addAll(chunk);
          received += chunk.length;
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        }
        bytes = chunks;
        break;
      }

      if (bytes == null || bytes.isEmpty) return null;

      // Verify the file starts with an APK magic header (ZIP format).
      if (bytes.length < 4) return null;
      if (bytes[0] != 0x50 || bytes[1] != 0x4B) {
        // Not a valid ZIP/APK — probably an HTML error page.
        return null;
      }

      // Integrity: compare against the release asset digest when known.
      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        if (!verifySha256(bytes, expectedSha256)) return null;
      }

      await file.writeAsBytes(bytes, flush: true);

      await _channel.invokeMethod('installApk', file.path);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

/// Pure check, split out for tests: hex compare of the SHA-256 over [bytes].
@pragma('vm:entry-point')
bool verifySha256(List<int> bytes, String expectedHex) {
  final expected = expectedHex.trim().toLowerCase();
  if (expected.length != 64) return false;
  final actual = crypto.sha256.convert(bytes).toString();
  return actual == expected;
}
