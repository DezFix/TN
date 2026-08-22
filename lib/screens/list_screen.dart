import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/dialogs.dart';
import '../src/models.dart';
import '../src/theme.dart';
import '../src/widgets.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final _search = TextEditingController();
  String _q = '';
  String? _folderFilter; // null = all chats

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    _search.dispose();
    super.dispose();
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  Future<void> _openChat(Chat chat, {String? scrollTo, bool highlight = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(model: widget.model, chatId: chat.id,
          scrollToEntryId: scrollTo, highlightEntryId: highlight ? scrollTo : null),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _newChat() async {
    final chat = await showChatEditDialog(context, widget.model);
    if (chat == null) return;
    chat.folderId = _folderFilter;
    widget.model.state.chats.add(chat);
    await widget.model.save();
    if (!mounted) return;
    setState(() {});
    await _openChat(chat);
  }

  Future<void> _chatCtxAt(Chat chat, Offset globalPos) async {
    final model = widget.model;
    final action = await showChatCtxPopup(context, model, chat, globalPos);
    if (action == null) return;
    switch (action) {
      case ChatAction.pin:
        chat.pinned = true;
      case ChatAction.unpin:
        chat.pinned = false;
      case ChatAction.moveToFolder:
        if (!mounted) return;
        final folderId = await showMoveToFolderPopup(context, model, globalPos);
        if (folderId == null) return;
        chat.folderId = folderId.isEmpty ? null : folderId;
      case ChatAction.edit:
        if (!mounted) return;
        final result = await showChatEditDialog(context, model, chat: chat);
        if (result == null) return;
      case ChatAction.delete:
        if (!mounted) return;
        final ok = await showDeleteChatDialog(context, model);
        if (ok != true) return;
        model.state.chats.removeWhere((c) => c.id == chat.id);
        model.state.entries.removeWhere((e) => e.chatId == chat.id);
        model.state.reminders.removeWhere((r) => r.chatId == chat.id);
    }
    await model.save();
    if (mounted) setState(() {});
  }

  Future<void> _folderCtxAt(Folder folder, Offset globalPos) async {
    final model = widget.model;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      color: model.p.modalBg,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(Rect.fromPoints(globalPos, globalPos), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: model.p.accent), const SizedBox(width: 10), Text(model.tr('edit_folder'), style: TextStyle(color: model.p.text))])),
        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), const SizedBox(width: 10), Text(model.tr('delete_folder_title'), style: TextStyle(color: Colors.redAccent))])),
      ],
    );
    if (action == null) return;
    if (action == 'edit') {
      if (!mounted) return;
      final name = await showFolderNameDialog(context, model, initial: folder.name);
      if (name == null) return;
      folder.name = name;
    } else {
      model.state.folders.removeWhere((f) => f.id == folder.id);
      for (final c in model.state.chats) {
        if (c.folderId == folder.id) c.folderId = null;
      }
      if (_folderFilter == folder.id) _folderFilter = null;
    }
    await model.save();
    if (mounted) setState(() {});
  }

  Future<void> _newFolder() async {
    final name = await showFolderNameDialog(context, widget.model);
    if (name == null) return;
    widget.model.state.folders.add(Folder(id: uid('f'), name: name));
    await widget.model.save();
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SettingsScreen(model: widget.model)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final p = model.p;
    final tr = model.tr;

    final body = _q.isEmpty ? _buildChats(model, p, tr) : _buildSearchResults(model, p, tr);

    return Scaffold(
      backgroundColor: p.bgList,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                      style: TextStyle(color: p.text),
                      decoration: InputDecoration(
                        hintText: tr('search_hint'),
                        hintStyle: TextStyle(color: p.textFaint),
                        prefixIcon: Icon(Icons.search, color: p.textFaint, size: 22),
                        filled: true,
                        fillColor: p.bgChat,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.settings, color: p.textSoft),
                    tooltip: tr('settings'),
                    onPressed: _openSettings,
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: _q.isEmpty
          ? FloatingActionButton(
              backgroundColor: p.accent,
              onPressed: _newChat,
              child: const Icon(Icons.edit, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildChats(AppModel model, Palette p, String Function(String, [List<String>?]) tr) {
    if (model.state.chats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('no_chats'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.textFaint, height: 1.5)),
        ),
      );
    }

    final visible = model.state.chats
        .where((c) => _folderFilter == null || c.folderId == _folderFilter)
        .toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        final la = model.state.entriesFor(a.id);
        final lb = model.state.entriesFor(b.id);
        final ta = la.isEmpty ? 0 : la.last.ts;
        final tb = lb.isEmpty ? 0 : lb.last.ts;
        return tb.compareTo(ta);
      });

    final rows = <Widget>[];
    for (final chat in visible) {
      final entries = model.state.entriesFor(chat.id);
      final last = entries.isEmpty ? null : entries.last;
      rows.add(GestureDetector(
        onLongPressStart: (d) => _chatCtxAt(chat, d.globalPosition),
        child: ChatRow(
          chat: chat,
          p: p,
          preview: last == null ? tr('no_entries') : entryPreview(last, tr),
          time: last == null ? '' : fmtTime(last.ts),
          onTap: () => _openChat(chat),
        ),
      ));
    }
    if (rows.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(tr('no_chats'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.textFaint, height: 1.5)),
        ),
      ));
    }

    return Column(
      children: [
        _buildFolderTabs(model, p, tr),
        Expanded(child: ListView(children: rows)),
      ],
    );
  }

  void _reorderFolders(int oldIndex, int newIndex) {
    final folders = widget.model.state.folders;
    if (newIndex > oldIndex) newIndex--;
    final item = folders.removeAt(oldIndex);
    folders.insert(newIndex, item);
    widget.model.save();
    if (mounted) setState(() {});
  }

  Widget _buildFolderTabs(AppModel model, Palette p, String Function(String, [List<String>?]) tr) {
    Widget chip({
      required String label,
      required bool selected,
      VoidCallback? onTap,
      VoidCallback? onLongPress,
      IconData? icon,
      Widget? trailing,
    }) =>
        GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? p.accent : p.bgChat,
              borderRadius: BorderRadius.circular(18),
              border: selected ? null : Border.all(color: p.divider.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: selected ? Colors.white : p.textSoft),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Colors.white : p.textSoft,
                    )),
                if (trailing != null) ...[const SizedBox(width: 4), trailing],
              ],
            ),
          ),
        );

    // Reorderable folders only
    final folders = model.state.folders;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          chip(
            label: tr('all_chats'),
            icon: Icons.chat_bubble_outline_rounded,
            selected: _folderFilter == null,
            onTap: () => setState(() => _folderFilter = null),
          ),
          const SizedBox(width: 6),
          if (folders.isEmpty)
            const SizedBox.shrink()
          else
            Expanded(
              child: SizedBox(
                height: 34,
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: true,
                  onReorder: _reorderFolders,
                  proxyDecorator: (child, index, anim) => Material(color: Colors.transparent, child: child),
                  children: [
                    for (int i = 0; i < folders.length; i++)
                      Padding(
                        key: ValueKey(folders[i].id),
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onLongPressStart: (d) => _folderCtxAt(folders[i], d.globalPosition),
                          child: chip(
                            label: folders[i].name,
                            icon: Icons.folder_outlined,
                            selected: _folderFilter == folders[i].id,
                            onTap: () => setState(() => _folderFilter = folders[i].id),
                            trailing: Icon(Icons.drag_indicator, size: 12, color: _folderFilter == folders[i].id ? Colors.white70 : p.textFaint),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (folders.isNotEmpty) const SizedBox(width: 2),
          chip(
            label: tr('new_folder'),
            icon: Icons.create_new_folder_outlined,
            selected: false,
            onTap: _newFolder,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(AppModel model, Palette p, String Function(String, [List<String>?]) tr) {
    final q = _q;
    final matchedChats = <Chat>[];
    final matchedEntries = <Entry>[];

    for (final c in model.state.chats) {
      if (c.name.toLowerCase().contains(q)) matchedChats.add(c);
    }
    for (final e in model.state.searchEntries(q)) {
      if (!matchedEntries.any((x) => x.id == e.id)) matchedEntries.add(e);
    }

    if (matchedChats.isEmpty && matchedEntries.isEmpty) {
      return Center(
        child: Text(tr('no_search_results', [q]),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.textFaint)),
      );
    }

    final rows = <Widget>[];
    for (final c in matchedChats) {
      rows.add(SearchResultRow(
        chat: c,
        p: p,
        snippet: tr('chat_subtitle'),
        onTap: () => _openChat(c),
      ));
    }
    for (final e in matchedEntries) {
      final chat = model.state.chatById(e.chatId);
      if (chat == null) continue;
      rows.add(SearchResultRow(
        chat: chat,
        p: p,
        snippet: snippetFor(e, q, tr),
        onTap: () => _openChat(chat, scrollTo: e.id, highlight: true),
      ));
    }

    return ListView(children: rows);
  }
}