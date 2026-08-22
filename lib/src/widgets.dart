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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _hex(chat.color), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: chat.icon != null && chat.icon!.isNotEmpty
          ? Text(chat.icon!, style: TextStyle(fontSize: iconSize))
          : Text(letter, style: TextStyle(fontSize: iconSize, color: Colors.white, fontWeight: FontWeight.w700)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(fontSize: 11.5, color: p.textFaint)),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          Icon(Icons.push_pin, size: 13, color: p.textFaint),
                          const SizedBox(width: 4),
                        ],
                        Text(chatKinds.firstWhere((k) => k.$1 == chat.kind, orElse: () => ('note', '📝')).$2, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: p.text)),
                        ),
                        if (time.isNotEmpty)
                          Text(time, style: TextStyle(fontSize: 11, color: p.textFaint)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: p.textSoft)),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    const SizedBox(height: 2),
                    Text(snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.textSoft)),
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