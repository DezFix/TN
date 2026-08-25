import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Drive backup sync via the Drive REST v3 API.
///
/// Uses an "installed app" OAuth client: the system browser opens the consent
/// page, a temporary loopback HTTP server catches the redirect, and the code
/// is exchanged for tokens. The exchange is protected with PKCE (S256) —
/// the recommended flow for native apps, no client secret involved.
/// OAuth credentials are injected at build time (kept out of the repo):
///   --dart-define=TN_GDRIVE_CLIENT_ID=...
class GoogleDriveClient {
  static const _clientId = String.fromEnvironment('TN_GDRIVE_CLIENT_ID');
  static const _scope = 'https://www.googleapis.com/auth/drive.file';
  static const _prefsKey = 'tn-cloud-gdrive';

  String? _refresh;
  String? _access;
  int _expiry = 0;

  /// PKCE verifier for the connect() in flight.
  String _codeVerifier = '';

  /// RFC 7636: 43-128 chars from an unreserved alphabet.
  static String generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(64, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static String codeChallengeS256(String verifier) =>
      base64Url.encode(crypto.sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  /// Machine-readable reason of the last failed connect() — used to show a
  /// helpful hint (wrong client type, account not in Test users, etc).
  String lastError = '';

  bool get isConnected => _refresh != null;

  static Future<GoogleDriveClient?> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['refresh'] is! String) return null;
      return GoogleDriveClient()
        .._refresh = json['refresh'] as String
        .._access = json['access'] as String?
        .._expiry = (json['expiry'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey,
          jsonEncode({
            'refresh': _refresh,
            'access': _access,
            'expiry': _expiry,
          }));
    } catch (_) {}
  }

  static Future<void> forget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// Opens the browser for consent and exchanges the returned code for
  /// tokens. Returns false on timeout / user cancel / HTTP error.
  Future<bool> connect() async {
    HttpServer? server;
    try {
      server =
          await HttpServer.bind('127.0.0.1', 0).timeout(const Duration(seconds: 5));
    } catch (_) {
      return false;
    }
    final port = server.port;
    final redirect = 'http://localhost:$port';
    _codeVerifier = generateCodeVerifier();
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': _scope,
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': codeChallengeS256(_codeVerifier),
      'code_challenge_method': 'S256',
    });
    try {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      await server.close(force: true);
      return false;
    }

    final codeCompleter = Completer<String?>();
    late final StreamSubscription<HttpRequest> sub;
    sub = server.listen((req) async {
      try {
        final err = req.uri.queryParameters['error'];
        req.response.headers.contentType = ContentType.html;
        if (err != null) {
          lastError = 'google:$err';
          req.response.write(
              '<html><body style="font-family:sans-serif;text-align:center;padding-top:40px">'
              '<h2>TN</h2><p>Authorization failed: $err</p></body></html>');
        } else {
          req.response.write(
              '<html><body style="font-family:sans-serif;text-align:center;padding-top:40px">'
              '<h2>TN</h2><p>OK — you can close this tab and return to the app.</p>'
              '</body></html>');
        }
        await req.response.close();
      } catch (_) {}
      if (!codeCompleter.isCompleted) {
        codeCompleter.complete(req.uri.queryParameters['code']);
      }
    });
    String? code;
    try {
      code = await codeCompleter.future.timeout(const Duration(minutes: 5));
    } catch (_) {}
    await sub.cancel();
    await server.close(force: true);
    if (code == null || code.isEmpty) return false;

    try {
      final resp = await http
          .post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            body: {
              'client_id': _clientId,
              'code': code,
              'grant_type': 'authorization_code',
              'redirect_uri': redirect,
              // PKCE: proves the app that started the flow is redeeming it.
              'code_verifier': _codeVerifier,
            },
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        // Google answers 400 with {"error": "redirect_uri_mismatch"} etc —
        // surface it so the UI can hint at the fix.
        try {
          lastError = 'google:${(jsonDecode(resp.body) as Map<String, dynamic>)['error']}';
        } catch (_) {
          lastError = 'http_${resp.statusCode}';
        }
        return false;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final refresh = json['refresh_token'] as String?;
      final access = json['access_token'] as String?;
      if (access == null) return false;
      _access = access;
      // prompt=consent guarantees a refresh token; keep an old one anyway.
      if (refresh != null) _refresh = refresh;
      _expiry = DateTime.now().millisecondsSinceEpoch +
          ((json['expires_in'] as num?)?.toInt() ?? 3600) * 1000 -
          60000;
      await save();
      return isConnected;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _token() async {
    if (_refresh == null) return null;
    if (_access != null && DateTime.now().millisecondsSinceEpoch < _expiry) {
      return _access;
    }
    try {
      final resp = await http
          .post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            body: {
              'client_id': _clientId,
              'grant_type': 'refresh_token',
              'refresh_token': _refresh,
            },
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final access = json['access_token'] as String?;
      if (access == null) return null;
      _access = access;
      _expiry = DateTime.now().millisecondsSinceEpoch +
          ((json['expires_in'] as num?)?.toInt() ?? 3600) * 1000 -
          60000;
      await save();
      return access;
    } catch (_) {
      return null;
    }
  }

  /// Find a file by exact [name]. Returns `null` if not found.
  Future<Map<String, dynamic>?> findFile(String name) async {
    final token = await _token();
    if (token == null) return null;
    try {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "name = '$name' and trashed=false",
        'pageSize': '1',
        'fields': 'files(id,modifiedTime)',
      });
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = (json['files'] as List?) ?? const [];
      return files.isEmpty ? null : (files.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Overwrite the content of an existing [fileId] with new [bytes].
  Future<bool> updateFile(String fileId, String name, List<int> bytes) async {
    final token = await _token();
    if (token == null) return false;
    try {
      final boundary = 'tn${DateTime.now().millisecondsSinceEpoch}x';
      final meta = jsonEncode({'name': name});
      final body = <int>[
        ...utf8.encode('--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$meta\r\n'
            '--$boundary\r\n'
            'Content-Type: application/zip\r\n\r\n'),
        ...bytes,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];
      final resp = await http
          .patch(
            Uri.parse(
                'https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=multipart'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> upload(String name, List<int> bytes) async {
    final token = await _token();
    if (token == null) return false;
    try {
      final boundary = 'tn${DateTime.now().millisecondsSinceEpoch}x';
      final meta = jsonEncode({'name': name});
      final body = <int>[
        ...utf8.encode('--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$meta\r\n'
            '--$boundary\r\n'
            'Content-Type: application/zip\r\n\r\n'),
        ...bytes,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];
      final resp = await http
          .post(
            Uri.parse(
                'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Backup file ids+names sorted oldest first (names embed a timestamp).
  Future<List<MapEntry<String, String>>> listBackups() async {
    final token = await _token();
    if (token == null) return const [];
    try {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "name contains 'tn-backup-' and trashed=false",
        'orderBy': 'name',
        'pageSize': '50',
        'fields': 'files(id,name)',
      });
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return const [];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = (json['files'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();
      final list = files
          .map((f) => MapEntry(f['id'] as String, f['name'] as String))
          .toList();
      list.sort((a, b) => a.value.compareTo(b.value));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> delete(String fileId) async {
    final token = await _token();
    if (token == null) return;
    try {
      await http.delete(
        Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  Future<List<int>?> download(String fileId) async {
    final token = await _token();
    if (token == null) return null;
    try {
      final resp = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) return null;
      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
