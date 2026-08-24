import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_model.dart';
import '../src/dialogs.dart';
import '../src/models.dart';
import '../src/theme.dart';

class FoldersEditScreen extends StatefulWidget {
  const FoldersEditScreen({super.key, required this.model});
  final AppModel model;
  @override
  State<FoldersEditScreen> createState() => _FoldersEditScreenState();
}

class _FoldersEditScreenState extends State<FoldersEditScreen> {
  Future<void> _edit(Folder folder) async {
    final result = await showFolderEditDialog(context, widget.model, folder: folder);
    if (result == null) return;
    HapticFeedback.lightImpact();
    widget.model.save();
    if (mounted) setState(() {});
  }

  Future<void> _delete(Folder folder) async {
    final p = widget.model.p;
    final tr = widget.model.tr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(tr('delete_folder_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        content: Text(tr('delete_folder_body'), style: TextStyle(fontSize: 14, color: p.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete'), style: TextStyle(color: p.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    HapticFeedback.mediumImpact();
    widget.model.state.folders.removeWhere((f) => f.id == folder.id);
    for (final c in widget.model.state.chats) {
      if (c.folderId == folder.id) c.folderId = null;
    }
    await widget.model.save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.model.p;
    final tr = widget.model.tr;
    final folders = widget.model.state.folders;

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: p.textSoft), onPressed: () => Navigator.pop(context)),
        title: Text(tr('folders_reorder'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Text(tr('folders_edit_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: p.textFaint, height: 1.4)),
            ),
            Expanded(
              child: folders.isEmpty
                  ? Center(child: Text(tr('nothing_found'), style: TextStyle(fontSize: 13.5, color: p.textFaint)))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: folders.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final f = folders.removeAt(oldIndex);
                          folders.insert(newIndex, f);
                        });
                        HapticFeedback.selectionClick();
                        widget.model.save();
                      },
                      proxyDecorator: (child, index, anim) => AnimatedBuilder(
                        animation: anim,
                        builder: (_, _) => Material(
                          color: p.bgChat,
                          elevation: 6 * anim.value,
                          shadowColor: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        ),
                      ),
                      itemBuilder: (ctx, i) {
                        final f = folders[i];
                        final color = f.color != null ? colorFromHex(f.color!) : null;
                        return Container(
                          key: ValueKey(f.id),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            leading: Icon(Icons.folder_outlined, size: 22, color: color ?? p.accent),
                            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: p.text)),
                            subtitle: Text(tr('tap_to_edit'), style: TextStyle(fontSize: 11, color: p.textFaint)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 21, color: p.danger),
                                  tooltip: tr('delete'),
                                  onPressed: () => _delete(f),
                                ),
                                Icon(Icons.drag_handle_rounded, size: 22, color: p.textFaint),
                              ],
                            ),
                            onTap: () => _edit(f),
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
