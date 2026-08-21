import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'models.dart';
import 'state.dart';
import 'package:path_provider/path_provider.dart';

class RssService {
  static const _cacheKey = 'tn-rss-cache';

  static Future<void> fetchForChat(Chat chat, AppState state) async {
    final url = chat.rssUrl;
    if (url == null || url.isEmpty) return;
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final doc = XmlDocument.parse(res.body);
      final items = _parseItems(doc);
      if (items.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final rawCache = prefs.getString(_cacheKey);
      final cache = rawCache == null ? <String, dynamic>{} : jsonDecode(rawCache) as Map<String, dynamic>;
      final seen = (cache[chat.id] as List?)?.map((e) => e as String).toSet() ?? <String>{};
      var added = 0;
      for (final it in items.take(20)) {
        final id = it.guid.isNotEmpty ? it.guid : it.link.isNotEmpty ? it.link : it.title;
        if (seen.contains(id)) continue;
        seen.add(id);
        final text = it.title + (it.link.isNotEmpty ? '\n${it.link}' : '') + (it.desc.isNotEmpty ? '\n\n${it.desc}' : '');
        String? mediaName;
        String mediaType = 'text';
        if (it.imageUrl != null && it.imageUrl!.isNotEmpty) {
          try {
            final imgRes = await http.get(Uri.parse(it.imageUrl!)).timeout(const Duration(seconds: 10));
            if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
              final tmpPath = '${Directory.systemTemp.path}/${uid('rssimg')}.jpg';
              final tmpFile = File(tmpPath);
              await tmpFile.writeAsBytes(imgRes.bodyBytes);
              // save via MediaStore if available, else keep tmp
              try {
                // dynamic import to avoid circular: use simple file copy to media dir
                final mediaDir = await getMediaDir();
                final name = '${uid('img')}.jpg';
                final dest = File('${mediaDir.path}/$name');
                await tmpFile.copy(dest.path);
                await tmpFile.delete();
                mediaName = name;
                mediaType = 'image';
              } catch (_) {
                mediaName = null;
              }
            }
          } catch (_) {}
        }
        state.entries.add(Entry(
          id: uid('e'),
          chatId: chat.id,
          type: mediaType,
          ts: it.pubDate ?? DateTime.now().millisecondsSinceEpoch,
          text: text,
          tags: extractTags(text),
          media: mediaName,
          mediaName: mediaName,
        ));
        added++;
        if (added >= 10) break;
      }
      cache[chat.id] = seen.toList();
      await prefs.setString(_cacheKey, jsonEncode(cache));
      if (added > 0) await state.save();
    } catch (_) {}
  }

  static Future<void> fetchAll(AppState state) async {
    for (final c in state.chats) {
      if (c.rssUrl != null && c.rssUrl!.isNotEmpty) {
        await fetchForChat(c, state);
      }
    }
  }

  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }

  static List<_RssItem> _parseItems(XmlDocument doc) {
    final out = <_RssItem>[];
    // RSS 2.0 <item>, Atom <entry>
    for (final item in doc.findAllElements('item')) {
      String? img;
      final enc = item.findElements('enclosure').firstOrNull;
      if (enc != null && (enc.getAttribute('type')?.startsWith('image/') ?? false)) img = enc.getAttribute('url');
      if (img == null) {
        final media = item.findElements('media:content').firstOrNull ?? item.findElements('media:thumbnail').firstOrNull;
        if (media != null) img = media.getAttribute('url');
      }
      out.add(_RssItem(
        title: item.findElements('title').firstOrNull?.innerText.trim() ?? '',
        link: item.findElements('link').firstOrNull?.innerText.trim() ?? '',
        desc: item.findElements('description').firstOrNull?.innerText.trim() ?? item.findElements('content:encoded').firstOrNull?.innerText.trim() ?? '',
        guid: item.findElements('guid').firstOrNull?.innerText.trim() ?? '',
        pubDate: _parseDate(item.findElements('pubDate').firstOrNull?.innerText),
        imageUrl: img,
      ));
    }
    for (final entry in doc.findAllElements('entry')) {
      final title = entry.findElements('title').firstOrNull?.innerText.trim() ?? '';
      String link = '';
      for (final l in entry.findElements('link')) {
        final href = l.getAttribute('href');
        if (href != null && href.isNotEmpty) { link = href; break; }
        if (l.innerText.trim().isNotEmpty) link = l.innerText.trim();
      }
      final guid = entry.findElements('id').firstOrNull?.innerText.trim() ?? link;
      String? img2;
      final media2 = entry.findElements('media:thumbnail').firstOrNull ?? entry.findElements('media:content').firstOrNull;
      if (media2 != null) img2 = media2.getAttribute('url');
      if (img2 == null) {
        // try link with image enclosure in atom content
        final enc2 = entry.findElements('link').where((e) => e.getAttribute('rel') == 'enclosure').firstOrNull;
        if (enc2 != null) img2 = enc2.getAttribute('href');
      }
      out.add(_RssItem(
        title: title,
        link: link,
        desc: entry.findElements('summary').firstOrNull?.innerText.trim() ?? entry.findElements('content').firstOrNull?.innerText.trim() ?? '',
        guid: guid,
        pubDate: _parseDate(entry.findElements('updated').firstOrNull?.innerText ?? entry.findElements('published').firstOrNull?.innerText),
        imageUrl: img2,
      ));
    }
    // sort newest first
    out.sort((a, b) => (b.pubDate ?? 0).compareTo(a.pubDate ?? 0));
    return out;
  }

  static int? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final dt = DateTime.parse(raw);
      return dt.millisecondsSinceEpoch;
    } catch (_) {
      try {
        // RSS pubDate like "Mon, 06 Jan 2025 12:00:00 GMT"
        final dt = HttpDate.parse(raw);
        return dt.millisecondsSinceEpoch;
      } catch (_) {}
    }
    return null;
  }
}

Future<Directory> getMediaDir() async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/$mediaDirName');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

class _RssItem {
  _RssItem({required this.title, required this.link, required this.desc, required this.guid, this.pubDate, this.imageUrl});
  final String title;
  final String link;
  final String desc;
  final String guid;
  final int? pubDate;
  final String? imageUrl;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
