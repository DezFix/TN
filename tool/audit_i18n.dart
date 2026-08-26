// Prints per-locale key differences vs the ru baseline.
import 'dart:io';

void main() {
  final src = File('lib/src/i18n.dart').readAsStringSync();
  final blockRe = RegExp(r"^  '(\w{2})': \{", multiLine: true);
  final keyRe = RegExp(r"'([a-z0-9_]+)':");
  final matches = blockRe.allMatches(src).toList();
  final maps = <String, Set<String>>{};
  for (var i = 0; i < matches.length; i++) {
    final lang = matches[i].group(1)!;
    final end =
        i + 1 < matches.length ? matches[i + 1].start : src.length;
    maps[lang] =
        keyRe.allMatches(src.substring(matches[i].end, end)).map((m) => m.group(1)!).toSet();
  }
  final base = maps['ru']!;
  for (final e in maps.entries) {
    final missingFromLang = base.difference(e.value);
    final extraInLang = e.value.difference(base);
    if (missingFromLang.isNotEmpty || extraInLang.isNotEmpty) {
      stdout.writeln('lang ${e.key}:'
          ' missing=${missingFromLang.toList()..sort()}'
          ' extra=${extraInLang.toList()..sort()}');
    } else {
      stdout.writeln('lang ${e.key}: OK');
    }
  }
}
