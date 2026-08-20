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
    widget.model.state.chats.add(chat);
    await widget.model.save();
    if (!mounted) return;
    setState(() {});
    await _openChat(chat);
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

    final rows = <Widget>[];
    for (final chat in model.state.chats) {
      final entries = model.state.entriesFor(chat.id);
      final last = entries.isEmpty ? null : entries.last;
      rows.add(ChatRow(
        chat: chat,
        p: p,
        preview: last == null ? tr('no_entries') : entryPreview(last, tr),
        time: last == null ? '' : fmtTime(last.ts),
        onTap: () => _openChat(chat),
      ));
    }

    return ListView(children: rows);
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