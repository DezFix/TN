import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

/// Minimal WebDAV client — enough for Nextcloud backups without any vendor
/// SDK. Server example: https://cloud.example.com
class NextcloudClient {
  NextcloudClient({required this.server, required this.user, required this.pass});

  final String server;
  final String user;
  final String pass;

  static const _dir = 'TN';

  String get _base {
    var s = server.trim();
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return '$s/remote.php/dav/files/$user';
  }

  Map<String, String> get _headers => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
      };

  Future<http.Response> _send(String method, Uri url,
      {Map<String, String>? headers, List<int>? body, Duration? timeout}) async {
    final req = http.Request(method, url)
      ..headers.addAll(headers ?? const {})
      ..followRedirects = false;
    if (body != null) req.bodyBytes = body;
    final streamed =
        await req.send().timeout(timeout ?? const Duration(seconds: 20));
    return http.Response.fromStream(streamed);
  }

  Future<bool> testConnection() async {
    try {
      final res = await _send('PROPFIND', Uri.parse('$_base/$_dir/'),
          headers: {..._headers, 'Depth': '0'});
      // 207 multistatus = exists; 404 = create the folder on first connect.
      if (res.statusCode == 404) return await _ensureDir();
      return res.statusCode == 207;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureDir() async {
    try {
      final res =
          await _send('MKCOL', Uri.parse('$_base/$_dir'), headers: _headers);
      return res.statusCode == 201 || res.statusCode == 405;
    } catch (_) {
      return false;
    }
  }

  /// Uploads bytes as [name] into the TN folder. Returns true on success.
  Future<bool> upload(String name, List<int> bytes) async {
    try {
      if (!await testConnection()) return false;
      final res = await _send(
        'PUT',
        Uri.parse('$_base/$_dir/$name'),
        headers: {..._headers, 'Content-Type': 'application/zip'},
        body: bytes,
        timeout: const Duration(seconds: 120),
      );
      return res.statusCode == 200 ||
          res.statusCode == 201 ||
          res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// Names of all TN backups in the folder, oldest first by last-modified.
  Future<List<String>> listBackups() async {
    try {
      final res = await _send('PROPFIND', Uri.parse('$_base/$_dir/'),
          headers: {..._headers, 'Depth': '1'});
      if (res.statusCode != 207) return [];
      final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
      final names = <(DateTime, String)>[];
      for (final node in doc.findAllElements('response')) {
        final href = node
                .findAllElements('href')
                .firstOrNull
                ?.innerText ??
            '';
        if (!href.contains('.zip') || !href.contains('tn-backup')) continue;
        final modified = node
                .findAllElements('getlastmodified')
                .firstOrNull
                ?.innerText ??
            '';
        DateTime when;
        try {
          when = HttpDate.parse(modified);
        } catch (_) {
          when = DateTime.fromMillisecondsSinceEpoch(0);
        }
        final name = Uri.decodeComponent(
            href.split('/').where((s) => s.isNotEmpty).last);
        names.add((when, name));
      }
      names.sort((a, b) => a.$1.compareTo(b.$1));
      return names.map((n) => n.$2).toList();
    } catch (_) {
      return [];
    }
  }

  /// Downloads [name] from the TN folder; null on failure.
  Future<List<int>?> download(String name) async {
    try {
      final res = await _send('GET', Uri.parse('$_base/$_dir/$name'),
          headers: _headers, timeout: const Duration(seconds: 60));
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  // ---- persisted account ----

  static Future<NextcloudClient?> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('tn-cloud-nextcloud');
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final server = j['server'] as String? ?? '';
      final user = j['user'] as String? ?? '';
      final pass = j['pass'] as String? ?? '';
      if (server.isEmpty || user.isEmpty) return null;
      return NextcloudClient(server: server, user: user, pass: pass);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tn-cloud-nextcloud',
        jsonEncode({'server': server, 'user': user, 'pass': pass}));
  }

  static Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tn-cloud-nextcloud');
  }
}

extension _FirstOf<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
