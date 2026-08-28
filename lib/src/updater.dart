import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class Updater {
  static const _channel = MethodChannel('tn/install');

  /// Machine-readable reason of the last failed [downloadAndInstall]:
  /// 'no_sha' (no digest to verify against) | 'sha_mismatch' | 'truncated'
  /// | 'not_apk' | 'network' | 'empty'
  /// | 'INSTALL_FAILED' (native installer rejected the package).
  ///
  /// `no_sha` is the safety case we never swallow: the package is NOT shipped
  /// to the installer unless we could verify its SHA-256, because an
  /// unverified file is exactly what produced the recurring "package
  /// corrupted" update failures. If no digest is available the update simply
  /// refuses to install and asks the user to retry.
  static String lastError = '';

  /// Numeric compare of "vX.Y.Z" tags against the installed version.
  /// Pre-release suffixes ("1.2.3-beta") are handled: same numeric version
  /// but tag is stable and current is pre-release → stable is newer.
  static bool isNewerTag(String tag, String current) {
    bool isPre(String s) => s.contains('-');
    List<int> parse(String s) => s
        .replaceFirst(RegExp('^v'), '')
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp('[^0-9].*'), '')) ?? 0)
        .toList();
    final a = parse(tag), b = parse(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    // Numeric equal → stable > pre-release.
    if (isPre(current) && !isPre(tag)) return true;
    return false;
  }

  /// Downloads an APK from [url] to the cache directory, then triggers the
  /// Android package installer via a platform channel.
  /// [expectedSha256] (hex, from the GitHub release asset digest) is verified
  /// before anything is handed to the package installer — the old magic-bytes
  /// check only proved the payload was *a* zip, not *our* APK.
  ///
  /// [expectedSha256] is REQUIRED: without a digest to verify against the
  /// package is never downloaded nor installed (lastError = 'no_sha'). This
  /// guarantees a truncated/mid-corrupted download can never reach the system
  /// installer and surface as "package corrupted".
  ///
  /// Returns the path of the downloaded file, or null on error (see
  /// [lastError]).
  static Future<String?> downloadAndInstall(
    String url,
    void Function(double progress)? onProgress, {
    String? expectedSha256,
  }) async {
    lastError = '';
    if (expectedSha256 == null || expectedSha256.trim().isEmpty) {
      lastError = 'no_sha';
      return null;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}tn-update.apk');
      // A stale half-written file from a previous session must never be
      // mistaken for the fresh download.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}

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
          if (location == null || location.isEmpty) {
            lastError = 'network';
            return null;
          }
          currentUrl = location;
          continue;
        }

        if (resp.statusCode != 200) {
          lastError = 'http_${resp.statusCode}';
          return null;
        }

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

      if (bytes == null || bytes.isEmpty) {
        lastError = 'empty';
        return null;
      }

      // Container sanity BEFORE any hashing: a real APK starts with a local
      // file header and MUST contain an End-of-Central-Directory record near
      // the tail. A truncated download passes the old 2-byte magic check but
      // then Android reports "package corrupted" — exactly the recurring
      // user report this is meant to diagnose.
      if (!validateZipContainer(bytes)) {
        lastError =
            bytes[0] == 0x50 && bytes[1] == 0x4B ? 'truncated' : 'not_apk';
        return null;
      }

      // Integrity: REQUIRED digest check. A missing/invalid digest aborted
      // earlier as 'no_sha', so this always runs against a known value — the
      // system installer can only ever receive a byte-verified APK.
      if (!verifySha256(bytes, expectedSha256)) {
        lastError = 'sha_mismatch';
        return null;
      }

      await file.writeAsBytes(bytes, flush: true);

      try {
        await _channel.invokeMethod('installApk', file.path);
      } on PlatformException catch (e) {
        // Native side rejected the install attempt (signature mismatch,
        // parse failure, installer refused). Surfaced so the UI can explain
        // instead of silently resetting the dialog.
        lastError =
            e.code == 'INSTALL_FAILED' ? 'INSTALL_FAILED' : 'native_${e.code}';
        return null;
      }
      return file.path;
    } catch (_) {
      lastError = 'network';
      return null;
    }
  }
}

/// Pure container validation, split out for tests: ZIP starts with the local
/// file header `PK\x03\x04` and ends (within the last 64 KB + comment room)
/// with an End-of-Central-Directory record `PK\x05\x06`.
bool validateZipContainer(List<int> bytes) {
  if (bytes.length < 8) return false;
  if (bytes[0] != 0x50 || bytes[1] != 0x4B || bytes[2] != 0x03 || bytes[3] != 0x04) {
    return false;
  }
  final windowStart = bytes.length - 65536 < 0 ? 0 : bytes.length - 65536;
  for (var i = bytes.length - 22; i >= windowStart; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4B &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      return true;
    }
  }
  return false;
}

/// Pure check, split out for tests: hex compare of the SHA-256 over [bytes].
@pragma('vm:entry-point')
bool verifySha256(List<int> bytes, String expectedHex) {
  final expected = expectedHex.trim().toLowerCase();
  if (expected.length != 64) return false;
  final actual = crypto.sha256.convert(bytes).toString();
  return actual == expected;
}
