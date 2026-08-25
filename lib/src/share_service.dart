import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'media.dart';
import 'models.dart';
class ShareService {
  /// Share single entry: if image -> share file, else share text
  static Future<void> shareEntry(Entry e) async {
    if (e.type == 'image' && e.media != null) {
      final path = await MediaStore().pathOf(e.media!);
      final file = File(path);
      if (!await file.exists()) {
        await Share.share(e.text.isNotEmpty ? e.text : 'Фото');
        return;
      }
      final xfile = XFile(path, mimeType: 'image/jpeg', name: e.mediaName ?? 'photo.jpg');
      final text = e.text.isNotEmpty ? e.text : null;
      await Share.shareXFiles([xfile], text: text);
      return;
    }
    if (e.type == 'audio' && e.media != null) {
      final path = await MediaStore().pathOf(e.media!);
      final file = File(path);
      if (await file.exists()) {
        final xfile = XFile(path, mimeType: 'audio/m4a', name: e.mediaName ?? e.media ?? 'audio.m4a');
        await Share.shareXFiles([xfile], text: e.text.isNotEmpty ? e.text : null);
        return;
      }
    }
    // todo or text
    final text = _entryToText(e);
    if (text.trim().isEmpty) return;
    await Share.share(text);
  }

  static String _entryToText(Entry e) {
    if (e.type == 'todo') {
      final items = e.items ?? const <TodoItem>[];
      return items.map((i) => '${i.done ? '☑' : '☐'} ${i.text}').join('\n');
    }
    if (e.text.isNotEmpty) return e.text;
    if (e.tags.isNotEmpty) return e.tags.map((t) => '#$t').join(' ');
    return '';
  }

  /// Share multiple entries combined
  static Future<void> shareEntries(List<Entry> entries) async {
    if (entries.isEmpty) return;
    // if single image -> share file directly
    if (entries.length == 1) {
      await shareEntry(entries.first);
      return;
    }
    // Collect files + texts
    final files = <XFile>[];
    final texts = <String>[];
    for (final e in entries) {
      if ((e.type == 'image' || e.type == 'audio') && e.media != null) {
        final path = await MediaStore().pathOf(e.media!);
        if (await File(path).exists()) {
          files.add(XFile(path, name: e.mediaName ?? e.media ?? 'file'));
          if (e.text.isNotEmpty) texts.add(e.text);
          if (e.type == 'todo') texts.add(_entryToText(e));
          continue;
        }
      }
      final t = _entryToText(e);
      if (t.isNotEmpty) texts.add(t);
    }
    if (files.isNotEmpty) {
      final combined = texts.isNotEmpty ? texts.join('\n\n') : null;
      await Share.shareXFiles(files, text: combined);
    } else if (texts.isNotEmpty) {
      await Share.share(texts.join('\n\n'));
    }
  }

  /// Download image entry to Downloads folder
  static Future<String?> downloadImage(Entry e) async {    if (e.media == null) return null;
    final srcPath = await MediaStore().pathOf(e.media!);
    final srcFile = File(srcPath);
    if (!await srcFile.exists()) return null;
    try {
      Directory? downloads;
      try {
        downloads = await getDownloadsDirectory();
      } catch (_) {}
      if (downloads == null) {
        try {
          final ext = await getExternalStorageDirectory();
          if (ext != null) {
            // try to guess Download folder: /storage/emulated/0/Download
            final guess = Directory('/storage/emulated/0/Download');
            if (await guess.exists()) {
              downloads = guess;
            } else {
              downloads = ext;
            }
          }
        } catch (_) {}
      }
      downloads ??= await getApplicationDocumentsDirectory();
      final name = e.mediaName ?? e.media ?? 'photo.jpg';
      // ensure unique
      var destPath = '${downloads.path}${Platform.pathSeparator}$name';
      var counter = 1;
      while (await File(destPath).exists()) {
        final dot = name.lastIndexOf('.');
        final base = dot >= 0 ? name.substring(0, dot) : name;
        final ext = dot >= 0 ? name.substring(dot) : '';
        destPath = '${downloads.path}${Platform.pathSeparator}${base}_$counter$ext';
        counter++;
      }
      await srcFile.copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// Render [entries] (oldest first) as a Markdown document — the whole chat
  /// becomes a portable file via the system share sheet. Pure part is split
  /// out for tests.
  static String entryToMarkdown(Entry e) {
    final buf = StringBuffer();
    final when = DateTime.fromMillisecondsSinceEpoch(e.ts).toIso8601String();
    switch (e.type) {
      case 'todo':
        for (final i in e.items ?? const <TodoItem>[]) {
          buf.writeln('- [${i.done ? 'x' : ' '}] ${i.text}');
        }
        break;
      case 'image':
        buf.writeln('![${e.text.isNotEmpty ? e.text.replaceAll('\n', ' ') : e.mediaName}]()');
        if (e.text.isNotEmpty) buf.writeln();
        buf.writeln(e.text);
        break;
      default:
        buf.writeln(e.text);
    }
    final head = '**$when**';
    return '$head\n${buf.toString().trim()}';
  }

  static Future<void> exportChatMarkdown(String chatName, List<Entry> entries) async {
    if (entries.isEmpty) return;
    final sorted = List<Entry>.of(entries)..sort((a, b) => a.ts.compareTo(b.ts));
    final md = StringBuffer('# $chatName\n\n');
    for (final e in sorted) {
      md.writeln(entryToMarkdown(e));
      md.writeln();
    }
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = chatName.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    final f = File('${dir.path}${Platform.pathSeparator}tn-$safeName-$stamp.md');
    await f.writeAsString(md.toString(), flush: true);
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/markdown')]);
  }
}
