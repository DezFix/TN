import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_lock.dart';
import '../src/app_model.dart';
import '../src/chat_lock.dart';
import '../src/dialogs.dart';
import '../src/folder_tabs.dart';
import '../src/models.dart';

/// Reorder every folder tab (smart tasks/notes, tags, agenda, calendar and
/// the user's own folders) and toggle the built-in ones.
class FolderTabsOrderScreen extends StatefulWidget {
  const FolderTabsOrderScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<FolderTabsOrderScreen> createState() => _FolderTabsOrderScreenState();
}

class _FolderTabsOrderScreenState extends State<FolderTabsOrderScreen> {
  List<String> _order = const [];
  Map<String, bool> _enabled = {
    for (final id in FolderTabs.builtin) id: true,
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await FolderTabs.loadEnabled();
    final order = await FolderTabs.loadOrder(
      widget.model.state.folders.map((f) => f.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _order = order;
      _loading = false;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final next = List<String>.of(_order);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    setState(() => _order = next);
    FolderTabs.saveOrder(next);
    HapticFeedback.selectionClick();
  }

  Folder? _folder(String id) {
    for (final f in widget.model.state.folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> _edit(Folder folder) async {
    final result = await showFolderEditDialog(
      context,
      widget.model,
      folder: folder,
    );
    if (result == null) return;
    await widget.model.save();
    if (mounted) await _load();
  }

  Future<void> _delete(Folder folder) async {
    final tr = widget.model.tr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.model.p.modalBg,
        title: Text(
          tr('delete_folder_title'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: widget.model.p.text,
          ),
        ),
        content: Text(
          tr('delete_folder_body'),
          style: TextStyle(fontSize: 14, color: widget.model.p.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              tr('delete'),
              style: TextStyle(color: widget.model.p.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.model.state.folders.removeWhere((f) => f.id == folder.id);
    for (final c in widget.model.state.chats) {
      if (c.folderId == folder.id) c.folderId = null;
    }
    await ChatLock.setFolder(folder.id, false);
    await widget.model.save();
    await FolderTabs.syncFolderOrder(
      widget.model.state.folders.map((f) => f.id).toList(),
    );
    if (mounted) await _load();
  }

  Future<void> _toggleLock(Folder folder) async {
    final tr = widget.model.tr;
    if (!AppLock.supported || !await AppLock.isEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('lock_need_setup'))),
        );
      }
      return;
    }
    await ChatLock.setFolder(
      folder.id,
      !ChatLock.isFolderLocked(folder.id),
    );
    if (mounted) setState(() {});
  }

  String _label(String id, String Function(String, [List<String>?]) tr) {
    switch (id) {
      case 'smart_tasks':
        return tr('smart_tasks');
      case 'smart_notes':
        return tr('smart_notes');
      case 'tags':
        return tr('tags_title');
      case 'agenda':
        return tr('agenda_title');
      case 'calendar':
        return tr('calendar_title');
    }
    return _folder(id)?.name ?? id;
  }

  IconData _icon(String id) {
    if (id == 'smart_tasks') return Icons.check_circle_outline;
    if (id == 'smart_notes') return Icons.note_alt_outlined;
    if (id == 'tags') return Icons.tag;
    if (id == 'agenda') return Icons.event_outlined;
    if (id == 'calendar') return Icons.calendar_month_outlined;
    return Icons.folder_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.model.p;
    final tr = widget.model.tr;

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
          tr('tabs_order'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                    child: Text(
                      tr('tabs_order_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: p.textFaint,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      buildDefaultDragHandles: false,
                      itemCount: _order.length,
                      onReorder: _reorder,
                      itemBuilder: (ctx, i) {
                        final id = _order[i];
                        final folder = _folder(id);
                        if (!FolderTabs.isBuiltin(id) && folder == null) {
                          return SizedBox.shrink(key: ValueKey(id));
                        }
                        final on = _enabled[id] ?? true;
                        return Container(
                          key: ValueKey(id),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: p.bgChat,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onTap: folder == null ? null : () => _edit(folder),
                              leading: Icon(
                                _icon(id),
                                size: 20,
                                color: on ? p.accent : p.textFaint,
                              ),
                              title: Text(
                                _label(id, tr),
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: on ? p.text : p.textFaint,
                                ),
                              ),
                              subtitle: FolderTabs.isBuiltin(id)
                                  ? Text(
                                      tr('smart_folder'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.textFaint,
                                      ),
                                    )
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (FolderTabs.isBuiltin(id))
                                    Switch(
                                      value: on,
                                      activeColor: p.accent,
                                      onChanged: (v) {
                                        setState(() => _enabled[id] = v);
                                        FolderTabs.setEnabled(id, v);
                                      },
                                    )
                                  else if (folder != null) ...[
                                    if (AppLock.supported)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(
                                          ChatLock.isFolderLocked(folder.id)
                                              ? Icons.lock_rounded
                                              : Icons.lock_open_rounded,
                                          size: 19,
                                          color: ChatLock.isFolderLocked(
                                                  folder.id)
                                              ? p.accent
                                              : p.textSoft,
                                        ),
                                        tooltip: tr(
                                          ChatLock.isFolderLocked(folder.id)
                                              ? 'unlock_folder'
                                              : 'lock_folder',
                                        ),
                                        onPressed: () => _toggleLock(folder),
                                      ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: p.danger,
                                      ),
                                      tooltip: tr('delete'),
                                      onPressed: () => _delete(folder),
                                    ),
                                  ],
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      size: 22,
                                      color: p.textFaint,
                                    ),
                                  ),
                                ],
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
