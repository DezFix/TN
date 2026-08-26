
import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/updater.dart';

void main() {
  group('isNewerTag (update notification version compare)', () {
    test('equal versions are not newer', () {
      expect(Updater.isNewerTag('v1.15.1', '1.15.1'), isFalse);
      expect(Updater.isNewerTag('1.15.1', 'v1.15.1'), isFalse);
    });

    test('greater patch/minor/major detected', () {
      expect(Updater.isNewerTag('v1.15.2', '1.15.1'), isTrue);
      expect(Updater.isNewerTag('v1.16.0', '1.15.9'), isTrue);
      expect(Updater.isNewerTag('v2.0.0', '1.99.99'), isTrue);
    });

    test('older tags are not newer', () {
      expect(Updater.isNewerTag('v1.15.0', '1.15.1'), isFalse);
      expect(Updater.isNewerTag('v1.14.9', '1.15.0'), isFalse);
    });

    test('missing components count as zero; suffixes ignored', () {
      expect(Updater.isNewerTag('v1.16', '1.15.5'), isTrue);
      expect(Updater.isNewerTag('v1.15', '1.15.1'), isFalse);
      // "3-beta" parses as 3 — pre-release flag does not break compare.
      expect(Updater.isNewerTag('v1.15.2-beta', '1.15.1'), isTrue);
    });
  });

  group('apk asset selection from a release payload', () {
    /// Mirrors the selection loop in main._maybeShowWhatsNew.
    ({String? url, String? sha}) pick(List<Map<String, dynamic>> assets) {
      String? universalUrl, universalSha, fallbackUrl, fallbackSha;
      for (final map in assets) {
        final n = (map['name'] as String?) ?? '';
        if (!n.toLowerCase().endsWith('.apk')) continue;
        final u = map['browser_download_url'] as String? ?? '';
        final digest = (map['digest'] as String?) ?? '';
        final sha = digest.startsWith('sha256:') ? digest.substring(7) : '';
        if (n.contains('universal')) {
          universalUrl = u;
          universalSha = sha.isNotEmpty ? sha : null;
        } else if (fallbackUrl == null) {
          fallbackUrl = u;
          fallbackSha = sha.isNotEmpty ? sha : null;
        }
      }
      return (
        url: universalUrl ?? fallbackUrl,
        sha: universalUrl != null ? universalSha : fallbackSha,
      );
    }

    test('prefers universal apk, skips windows zip (old bug)', () {
      final r = pick([
        {'name': 'TN-1.0-windows-x64.zip', 'browser_download_url': 'https://x/win.zip'},
        {'name': 'TN-1.0-arm64.apk', 'browser_download_url': 'https://x/arm.apk'},
        {'name': 'TN-1.0-universal.apk', 'browser_download_url': 'https://x/uni.apk'},
      ]);
      expect(r.url, 'https://x/uni.apk');
    });

    test('falls back to an abi apk when universal missing', () {
      final r = pick([
        {'name': 'TN-1.0-windows-x64.zip', 'browser_download_url': 'https://x/win.zip'},
        {'name': 'TN-1.0-arm64.apk', 'browser_download_url': 'https://x/arm.apk'},
      ]);
      expect(r.url, 'https://x/arm.apk');
    });

    test('extracts sha256 from the GitHub digest field', () {
      final hex = 'a' * 64;
      final r = pick([
        {'name': 'app-universal.apk', 'digest': 'sha256:$hex', 'browser_download_url': 'https://x/u.apk'},
      ]);
      expect(r.sha, hex);
    });
  });
}
