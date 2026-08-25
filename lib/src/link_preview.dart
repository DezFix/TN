import 'dart:async';
import 'package:http/http.dart' as http;

/// Lightweight fetcher for OpenGraph / Twitter Card metadata that renders
/// compact link-preview cards beneath messages containing URLs.
class LinkPreviewData {
  final String title;
  final String description;
  final String? imageUrl;
  final String domain;

  const LinkPreviewData({
    required this.title,
    required this.description,
    this.imageUrl,
    required this.domain,
  });
}

class LinkPreview {
  static final _cache = <String, _Entry>{};

  /// Fetch preview metadata for [url].  Returns `null` on failure or when the
  /// server does not expose OG/Twitter tags.  Results are cached for 1 hour.
  static Future<LinkPreviewData?> fetch(String url) async {
    final cached = _cache[url];
    if (cached != null && DateTime.now().difference(cached.ts) < const Duration(hours: 1)) {
      return cached.data;
    }
    try {
      final uri = Uri.parse(url);
      // Timeout quick — don't hold up the UI.
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (TN-app)',
        'Accept': 'text/html',
      }).timeout(const Duration(seconds: 6));
      if (resp.statusCode < 200 || resp.statusCode >= 400) return null;

      final html = resp.body;
      final data = _parse(html, uri.host);
      if (data != null) _cache[url] = _Entry(data);
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Parse og:/twitter meta tags from raw HTML.
  static LinkPreviewData? _parse(String html, String host) {
    String? og(String prop) {
      final esc = RegExp.escape(prop);
      // Match both " and ' as attribute delimiters.
      for (final d in ['"', "'"]) {
        final pat1 = '<meta\\s+(?:property|name)=' + d + esc + d + '\\s+content=' + d + '([^' + d + ']*)' + d;
        final m1 = RegExp(pat1, caseSensitive: false).firstMatch(html);
        if (m1 != null) return m1.group(1);
        final pat2 = '<meta\\s+content=' + d + '([^' + d + ']*)' + d + '\\s+(?:property|name)=' + d + esc + d;
        final m2 = RegExp(pat2, caseSensitive: false).firstMatch(html);
        if (m2 != null) return m2.group(1);
      }
      return null;
    }

    final title = og('og:title') ?? og('twitter:title');
    final desc = og('og:description') ?? og('twitter:description') ?? og('description');
    final img = og('og:image') ?? og('twitter:image');

    if (title == null && desc == null) return null;
    return LinkPreviewData(
      title: title ?? host,
      description: desc ?? '',
      imageUrl: img?.isNotEmpty == true ? img : null,
      domain: host,
    );
  }
}

class _Entry {
  final LinkPreviewData data;
  final DateTime ts = DateTime.now();
  _Entry(this.data);
}
