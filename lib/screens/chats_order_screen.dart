import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_model.dart';
import '../src/models.dart';
import '../src/theme.dart';

/// Manual chat order: drag rows, positions persist as [Chat.order].
class ChatsOrderScreen extends StatefulWidget {
  const ChatsOrderScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<ChatsOrderScreen> createState() => _ChatsOrderScreenState();
}

class _ChatsOrderScreenState extends State<ChatsOrderScreen> {
  List<Chat> get _chats {
    return widget.model.state.chats.where((c) => !c.isTrashed).toList()
      ..sort((a, b) {
        if (a.order != b.order) return a.order.compareTo(b.order);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  void _reorder(int oldIndex, int newIndex) {
    final chats = _chats;
    if (newIndex > oldIndex) newIndex--;
    final moved = chats.removeAt(oldIndex);
    chats.insert(newIndex, moved);
    for (var i = 0; i < chats.length; i++) {
      chats[i].order = i;
    }
    HapticFeedback.selectionClick();
    widget.model.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.model.p;
    final tr = widget.model.tr;
    final chats = _chats;

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          tr('chats_order'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Text(
                tr('manual_order_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: p.textFaint, height: 1.4),
              ),
            ),
            Expanded(
              child: chats.isEmpty
                  ? Center(
                      child: Text(
                        tr('nothing_found'),
                        style: TextStyle(fontSize: 13.5, color: p.textFaint),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: chats.length,
                      onReorder: _reorder,
                      itemBuilder: (ctx, i) {
                        final chat = chats[i];
                        final color = colorFromHex(chat.color);
                        return Container(
                          key: ValueKey(chat.id),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: p.bgChat,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: .18),
                                child: Text(
                                  chat.icon ?? (chat.name.isEmpty ? '#' : chat.name[0]),
                                  style: TextStyle(color: color, fontSize: 16),
                                ),
                              ),
                              title: Text(
                                chat.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14.5, color: p.text),
                              ),
                              subtitle: chat.pinned
                                  ? Text(
                                      tr('pin'),
                                      style: TextStyle(fontSize: 11, color: p.textFaint),
                                    )
                                  : null,
                              trailing: Icon(
                                Icons.drag_handle_rounded,
                                size: 22,
                                color: p.textFaint,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
