import 'package:flutter/material.dart';

import 'app_model.dart';
import 'models.dart';
import 'theme.dart';

Color _hex(String hex) => colorFromHex(hex);

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.chat, this.size = 46, this.iconSize = 22});

  final Chat chat;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final letter = chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?';
    final bg = _hex(chat.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: chat.icon != null && chat.icon!.isNotEmpty
          ? Text(chat.icon!, style: TextStyle(fontSize: iconSize))
          : Text(letter, style: TextStyle(fontSize: iconSize * 0.72, color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
    );
  }
}

class DayPill extends StatelessWidget {
  const DayPill({super.key, required this.label, required this.p});

  final String label;
  final Palette p;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: p.bgChat,
          borderRadius: BorderRadius.circular(TNRadii.pill),
          border: Border.all(color: p.divider.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint, letterSpacing: 0.2)),
      ),
    );
  }
}

class ChatRow extends StatelessWidget {
  const ChatRow({
    super.key,
    required this.chat,
    required this.p,
    required this.preview,
    required this.time,
    required this.onTap,
    this.onLongPress,
    this.highlight = false,
  });

  final Chat chat;
  final Palette p;
  final String preview;
  final String time;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlight ? p.rowActive : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              ChatAvatar(chat: chat),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.pinned) ...[
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                            child: Icon(Icons.push_pin, size: 10, color: p.accent),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(chatKinds.firstWhere((k) => k.$1 == chat.kind, orElse: () => ('note', '📝')).$2, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TNTypography.chatTitle.copyWith(color: p.text)),
                        ),
                        if (time.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.bgChat,
                              borderRadius: BorderRadius.circular(TNRadii.pill),
                            ),
                            child: Text(time, style: TNTypography.time.copyWith(color: p.textFaint)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TNTypography.chatPreview.copyWith(color: p.textSoft)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    super.key,
    required this.chat,
    required this.p,
    required this.snippet,
    required this.onTap,
  });

  final Chat chat;
  final Palette p;
  final String snippet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              ChatAvatar(chat: chat, size: 38, iconSize: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                    const SizedBox(height: 3),
                    Text(snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.textSoft, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: p.textFaint.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

String snippetFor(Entry e, String q, String Function(String, [List<String>?]) tr) {
  final preview = entryPreview(e, tr);
  final low = preview.toLowerCase();
  final qi = low.indexOf(q.toLowerCase());
  if (qi >= 0) {
    final start = qi > 20 ? qi - 20 : 0;
    return '…${preview.substring(start, qi + q.length + 40 > preview.length ? preview.length : qi + q.length + 40)}';
  }
  return preview;
}
