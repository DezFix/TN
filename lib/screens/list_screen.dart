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

  Future<void> _chatCtx(Chat chat) async {
    final model = widget.model;
    final action = await showChatCtxSheet(context, model, chat);
    if (action == null) return;
    switch (action) {
      case ChatAction.pin:
        chat.pinned = true;
      case ChatAction.unpin:
        chat.pinned = false;
      case ChatAction.moveToFolder:
        if (!mounted) return;
        final folderId = await showMoveToFolderSheet(context, model);
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

  Future<void> _folderCtx(Folder folder) async {
    final model = widget.model;
    final tr = model.tr;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: model.p.modalBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: model.p.accent),
              title: Text(tr('edit_folder'),
                  style: TextStyle(fontSize: 15, color: model.p.text)),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(tr('delete_folder_title'),
                  style: TextStyle(fontSize: 15, color: Colors.redAccent)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
      rows.add(ChatRow(
        chat: chat,
        p: p,
        preview: last == null ? tr('no_entries') : entryPreview(last, tr),
        time: last == null ? '' : fmtTime(last.ts),
        onTap: () => _openChat(chat),
        onLongPress: () => _chatCtx(chat),
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

  Widget _buildFolderTabs(AppModel model, Palette p, String Function(String, [List<String>?]) tr) {
    Widget chip({
      required String label,
      required bool selected,
      VoidCallback? onTap,
      VoidCallback? onLongPress,
      IconData? icon,
    }) =>
        GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? p.accent : p.bgChat,
              borderRadius: BorderRadius.circular(18),
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
              ],
            ),
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            chip(
              label: tr('all_chats'),
              icon: Icons.chat_bubble_outline_rounded,
              selected: _folderFilter == null,
              onTap: () => setState(() => _folderFilter = null),
            ),
            const SizedBox(width: 6),
            for (final f in model.state.folders) ...[
              chip(
                label: f.name,
                icon: Icons.folder_outlined,
                selected: _folderFilter == f.id,
                onTap: () => setState(() => _folderFilter = f.id),
                onLongPress: () => _folderCtx(f),
              ),
              const SizedBox(width: 6),
            ],
            chip(
              label: tr('new_folder'),
              icon: Icons.create_new_folder_outlined,
              selected: false,
              onTap: _newFolder,
            ),
          ],
        ),
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