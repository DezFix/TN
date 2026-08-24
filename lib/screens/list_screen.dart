import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_model.dart';
import '../src/dialogs.dart';
import '../src/models.dart';
import '../src/theme.dart';
import '../src/widgets.dart';
import 'chat_edit_screen.dart';
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
  final _listCtrl = ScrollController();
  String _q = '';
  String? _folderFilter; // null = all chats
  final Set<String> _sel = {};
  bool _showArchive = false;
  double _topOver = 0;
  double _botOver = 0;

  bool get _selecting => _sel.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    _search.dispose();
    _listCtrl.dispose();
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
    final chat = await Navigator.push<Chat>(
      context,
      MaterialPageRoute(builder: (_) => ChatEditScreen(model: widget.model)),
    );
    if (chat == null) return;
    chat.folderId = _folderFilter;
    widget.model.state.chats.add(chat);
    await widget.model.save();
    if (!mounted) return;
    setState(() {});
    await _openChat(chat);
  }

  void _onRowTap(Chat chat) {
    if (_selecting) {
      setState(() {
        if (!_sel.remove(chat.id)) _sel.add(chat.id);
      });
    } else {
      _openChat(chat);
    }
  }

  void _onRowLongPress(Chat chat) {
    HapticFeedback.mediumImpact();
    if (_selecting) {
      setState(() {
        if (!_sel.remove(chat.id)) _sel.add(chat.id);
      });
    } else {
      setState(() => _sel.add(chat.id));
    }
  }

  Future<void> _bulkPin() async {
    final model = widget.model;
    final anyUnpinned = model.state.chats.any((c) => _sel.contains(c.id) && !c.pinned);
    for (final c in model.state.chats) {
      if (_sel.contains(c.id)) c.pinned = anyUnpinned;
    }
    await model.save();
    if (mounted) setState(() => _sel.clear());
  }

  Future<void> _bulkFolder(Offset pos) async {
    final model = widget.model;
    if (!mounted) return;
    final folderId = await showMoveToFolderPopup(context, model, pos);
    if (folderId == null) return;
    for (final c in model.state.chats) {
      if (_sel.contains(c.id)) c.folderId = folderId.isEmpty ? null : folderId;
    }
    await model.save();
    if (mounted) setState(() => _sel.clear());
  }

  Future<void> _bulkArchive(bool toArchive) async {
    final model = widget.model;
    for (final c in model.state.chats) {
      if (_sel.contains(c.id)) {
        c.archived = toArchive;
        if (toArchive) c.pinned = false;
      }
    }
    await model.save();
    if (!mounted) return;
    setState(() {
      _sel.clear();
      if (toArchive) _showArchive = true;
    });
  }

  Future<void> _bulkDelete() async {
    final model = widget.model;
    if (!mounted) return;
    final ok = await showDeleteChatDialog(context, model);
    if (ok != true) return;
    model.state.chats.removeWhere((c) => _sel.contains(c.id));
    model.state.entries.removeWhere((e) => _sel.contains(e.chatId));
    model.state.reminders.removeWhere((r) => _sel.contains(r.chatId));
    await model.save();
    if (mounted) setState(() => _sel.clear());
  }

  bool _onScrollNotification(Notification n) {
    if (n is OverscrollNotification) {
      final m = n.metrics;
      if (m.pixels <= 0 && n.overscroll < 0) {
        _topOver += n.overscroll;
        if (!_showArchive && _topOver < -70) {
          HapticFeedback.lightImpact();
          setState(() => _showArchive = true);
          if (_listCtrl.hasClients) {
            _listCtrl.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        }
      } else if (m.pixels >= m.maxScrollExtent && n.overscroll > 0) {
        _botOver += n.overscroll;
        if (_showArchive && _botOver > 70) {
          HapticFeedback.lightImpact();
          setState(() => _showArchive = false);
        }
      }
    } else if (n is ScrollEndNotification) {
      _topOver = 0;
      _botOver = 0;
    }
    return false;
  }

  Future<void> _newFolder() async {
    final result = await showFolderEditDialog(context, widget.model);
    if (result == null) return;
    widget.model.state.folders.add(result);
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, -0.2), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: _selecting
                    ? KeyedSubtree(
                        key: const ValueKey('sel'),
                        child: _buildSelectionBar(model, p, tr),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('search'),
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
            ),
                ),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: AnimatedScale(
        scale: (_q.isEmpty && !_selecting) ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: _q.isNotEmpty || _selecting,
          child: FloatingActionButton(
            backgroundColor: p.accent,
            onPressed: _newChat,
            child: const Icon(Icons.edit, color: Colors.white),
          ),
        ),
      ),
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

    final active = model.state.chats.where((c) => !c.archived).toList();
    final archived = model.state.chats.where((c) => c.archived).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final visible = active
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
    if (archived.isNotEmpty) {
      rows.add(_buildArchiveHeader(model, p, tr, archived.length));
      rows.add(AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: !_showArchive
            ? const SizedBox(width: double.infinity)
            : Column(
                children: [
                  for (final chat in archived)
                    _chatListRow(model, p, tr, chat),
                  const SizedBox(height: 8),
                ],
              ),
      ));
    }
    for (final chat in visible) {
      rows.add(_chatListRow(model, p, tr, chat));
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
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ListView(controller: _listCtrl, children: rows),
          ),
        ),
      ],
    );
  }

  Widget _chatListRow(AppModel model, Palette p,
      String Function(String, [List<String>?]) tr, Chat chat) {
    final entries = model.state.entriesFor(chat.id);
    final last = entries.isEmpty ? null : entries.last;
    return _buildChatRow(chat, p, tr,
        preview: last == null ? tr('no_entries') : entryPreview(last, tr),
        time: last == null ? '' : fmtTime(last.ts));
  }

  Widget _buildArchiveHeader(AppModel model, Palette p,
      String Function(String, [List<String>?]) tr, int count) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _showArchive = !_showArchive);
        if (_showArchive && _listCtrl.hasClients) {
          _listCtrl.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.bgChat,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(_showArchive ? Icons.archive : Icons.archive_outlined,
                size: 20, color: p.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${tr('archive')} · $count',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.text)),
            ),
            Icon(
                _showArchive
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 20,
                color: p.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _buildChatRow(Chat chat, Palette p,
      String Function(String, [List<String>?]) tr,
      {required String preview, required String time}) {
    final selected = _sel.contains(chat.id);
    return GestureDetector(
      onTap: () => _onRowTap(chat),
      onLongPressStart: (_) => _onRowLongPress(chat),
      child: Container(
        color:
            selected ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
        child: Stack(
          children: [
            ChatRow(
              chat: chat,
              p: p,
              preview: preview,
              time: time,
              onTap: () => _onRowTap(chat),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _selecting ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? p.accent
                              : (p.name == 'dark' ? p.bgList : Colors.white),
                          border: Border.all(
                            color: selected ? p.accent : p.textFaint,
                            width: 2,
                          ),
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                size: 22, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(AppModel model, Palette p,
      String Function(String, [List<String>?]) tr) {
    final allArchived =
        model.state.chats.any((c) => _sel.contains(c.id) && !c.archived) ==
            false;
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.close, color: p.textSoft),
          onPressed: () => setState(() => _sel.clear()),
        ),
        Expanded(
          child: Text(tr('selected', ['${_sel.length}']),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text)),
        ),
        IconButton(
          icon: Icon(Icons.push_pin_outlined, color: p.textSoft),
          tooltip: tr('pin'),
          onPressed: _bulkPin,
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _bulkFolder(d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.drive_file_move_outline, size: 24, color: p.textSoft),
          ),
        ),
        IconButton(
          icon: Icon(allArchived ? Icons.unarchive : Icons.archive_outlined,
              color: p.textSoft),
          tooltip: tr(allArchived ? 'from_archive' : 'to_archive'),
          onPressed: () => _bulkArchive(!allArchived),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: _bulkDelete,
        ),
      ],
    );
  }

  Widget _buildFolderTabs(AppModel model, Palette p, String Function(String, [List<String>?]) tr) {
    Widget chip({
      required String label,
      required bool selected,
      VoidCallback? onTap,
      Color? iconColor,
      IconData? icon,
      Widget? trailing,
    }) =>
        GestureDetector(
          onTap: onTap,
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
                  Icon(icon, size: 15, color: selected ? Colors.white : (iconColor ?? p.textSoft)),
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

    // Folder chips: tap = filter, long-press = context menu, reorder via edit screen
    final folders = model.state.folders;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(
              label: tr('all_chats'),
              icon: Icons.chat_bubble_outline_rounded,
              selected: _folderFilter == null,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _folderFilter = null);
              },
            ),
            for (final f in folders) ...[
              const SizedBox(width: 6),
              chip(
                label: f.name,
                icon: Icons.folder_outlined,
                iconColor: f.color != null ? colorFromHex(f.color!) : null,
                selected: _folderFilter == f.id,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _folderFilter = f.id);
                },
              ),
            ],
            const SizedBox(width: 6),
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