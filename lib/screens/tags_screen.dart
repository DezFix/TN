import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/state.dart';

/// All hashtags across every non-trashed chat with entry counts.
/// Picking a tag returns '#tag' to the caller (ListScreen pre-fills search).
class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key, required this.model});

  final AppModel model;

  /// tag -> entry count, sorted by count then name. Pure helper, tested.
  static Map<String, int> collectTags(AppState state) {
    final trashed = state.chats.where((c) => c.isTrashed).map((c) => c.id).toSet();
    final counts = <String, int>{};
    for (final e in state.entries) {
      if (trashed.contains(e.chatId)) continue;
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final keys = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return a.compareTo(b);
      });
    return {for (final k in keys) k: counts[k]!};
  }

  @override
  Widget build(BuildContext context) {
    final p = model.p;
    final tr = model.tr;
    final tags = collectTags(model.state);

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(tr('tags_title'),
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: tags.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('tags_hint'),
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13.5, color: p.textFaint, height: 1.5)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: tags.length,
              itemBuilder: (ctx, i) {
                final tag = tags.keys.elementAt(i);
                final count = tags[tag]!;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: p.bgChat,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Icon(Icons.tag, size: 20, color: p.accent),
                    title: Text(tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: p.accent)),
                    ),
                    onTap: () => Navigator.pop(context, '#$tag'),
                  ),
                );
              },
            ),
    );
  }
}
