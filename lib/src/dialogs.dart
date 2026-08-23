import 'package:flutter/material.dart';

import 'app_model.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

enum EntryAction { copy, edit, forward, delete, select, share, download }

Future<Chat?> showChatEditDialog(BuildContext context, AppModel model, {Chat? chat}) async {
  final p = model.p;
  final tr = model.tr;
  final nameField = TextEditingController(text: chat?.name ?? '');
  final rssField = TextEditingController(text: chat?.rssUrl ?? '');
  var selectedIcon = chat?.icon;
  var selectedColor = chat?.color ?? appColors[0];
  var selectedKind = chat?.kind ?? 'note';

  return showDialog<Chat>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(tr(chat != null ? 'edit_chat' : 'new_chat'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameField,
                  autofocus: true,
                  maxLength: 40,
                  style: TextStyle(color: p.text),
                  decoration: InputDecoration(
                    hintText: tr('chat_name_hint'),
                    hintStyle: TextStyle(color: p.textFaint),
                    counterText: '',
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.divider)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.accent)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr('kind_label'),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in chatKinds)
                      GestureDetector(
                        onTap: () => setState(() => selectedKind = k.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: selectedKind == k.$1 ? p.accent.withValues(alpha: .18) : p.bgChat,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: selectedKind == k.$1 ? p.accent : p.divider, width: 1.5),
                          ),
                          child: Text('${k.$2} ${tr('kind_${k.$1}')}', style: TextStyle(fontSize: 12, color: selectedKind == k.$1 ? p.accent : p.text)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(tr('icon'),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 110,
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final icon in appIcons)
                      GestureDetector(
                        onTap: () => setState(() => selectedIcon = icon),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: selectedIcon == icon ? p.accent.withValues(alpha: .18) : p.bgChat,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: selectedIcon == icon ? p.accent : p.divider, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(icon ?? '—', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                  ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr('color'),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final color in appColors)
                      GestureDetector(
                        onTap: () => setState(() => selectedColor = color),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: colorFromHex(color),
                            shape: BoxShape.circle,
                            border: selectedColor == color
                                ? Border.all(color: p.text, width: 2)
                                : null,
                          ),
                          child: selectedColor == color
                              ? Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                  ],
                ),
                if (selectedKind == 'rss') ...[
                  const SizedBox(height: 12),
                  const Text('RSS Atom',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF8A9BA8))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: rssField,
                    style: TextStyle(color: p.text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://example.com/rss',
                      hintStyle: TextStyle(color: p.textFaint, fontSize: 13),
                      isDense: true,
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.divider)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.accent)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'), style: TextStyle(color: p.textSoft)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            onPressed: () {
              final name = nameField.text.trim();
              if (name.isEmpty) return;
              final rss = rssField.text.trim();
              final result = chat ?? Chat(id: uid('c'), name: name, color: selectedColor, kind: selectedKind);
              result
                ..name = name
                ..icon = selectedIcon
                ..color = selectedColor
                ..kind = selectedKind
                ..rssUrl = rss.isEmpty ? null : rss;
              Navigator.pop(ctx, result);
            },
            child: Text(tr(chat != null ? 'save' : 'create')),
          ),
        ],
      ),
    ),
  );
}

Future<bool?> showDeleteChatDialog(BuildContext context, AppModel model) {
  final p = model.p;
  final tr = model.tr;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.modalBg,
      title: Text(tr('delete_chat_title'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
      content: Text(tr('delete_chat_body'), style: TextStyle(fontSize: 14, color: p.textSoft)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'), style: TextStyle(color: p.textSoft))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete'), style: TextStyle(color: p.danger))),
      ],
    ),
  );
}

Future<bool?> showDeleteEntryDialog(BuildContext context, AppModel model) {
  final p = model.p;
  final tr = model.tr;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.modalBg,
      title: Text(tr('delete_entry_title'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'), style: TextStyle(color: p.textSoft))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete'), style: TextStyle(color: p.danger))),
      ],
    ),
  );
}

Future<EntryAction?> showEntryCtxPopup(BuildContext context, AppModel model, Entry entry, Offset globalPos) {
  final p = model.p;
  final tr = model.tr;
  final canEdit = entry.type == 'text' || entry.type == 'todo';
  final isImage = entry.type == 'image';
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<EntryAction>(
    context: context,
    color: p.modalBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    position: RelativeRect.fromRect(Rect.fromPoints(globalPos, globalPos), Offset.zero & overlay.size),
    items: [
      PopupMenuItem(value: EntryAction.select, child: Row(children: [Icon(Icons.checklist, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr('select'), style: TextStyle(color: p.text))])),
      if (canEdit) PopupMenuItem(value: EntryAction.copy, child: Row(children: [Icon(Icons.copy, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(tr('copy'), style: TextStyle(color: p.text))])),
      if (canEdit) PopupMenuItem(value: EntryAction.edit, child: Row(children: [Icon(Icons.edit, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(tr('edit'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: EntryAction.forward, child: Row(children: [Icon(Icons.forward, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(tr('forward'), style: TextStyle(color: p.text))])),
      // external share
      PopupMenuItem(value: EntryAction.share, child: Row(children: [Icon(Icons.share, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr(isImage ? 'share_photo' : 'share_text'), style: TextStyle(color: p.text))])),
      if (isImage) PopupMenuItem(value: EntryAction.download, child: Row(children: [Icon(Icons.download, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(tr('download'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: EntryAction.delete, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: p.danger), const SizedBox(width: 10), Text(tr('delete'), style: TextStyle(color: p.danger))])),
    ],
  );
}

Future<EntryAction?> showEntryCtxSheet(BuildContext context, AppModel model, Entry entry) {
  final p = model.p;
  final tr = model.tr;
  final canEdit = entry.type == 'text' || entry.type == 'todo';
  return showModalBottomSheet<EntryAction>(
    context: context,
    backgroundColor: p.modalBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canEdit) ...[
            ListTile(
              leading: Icon(Icons.copy, color: p.textSoft),
              title: Text(tr('copy'), style: TextStyle(color: p.text)),
              onTap: () => Navigator.pop(ctx, EntryAction.copy),
            ),
            ListTile(
              leading: Icon(Icons.edit, color: p.textSoft),
              title: Text(tr('edit'), style: TextStyle(color: p.text)),
              onTap: () => Navigator.pop(ctx, EntryAction.edit),
            ),
          ],
          ListTile(
            leading: Icon(Icons.forward, color: p.textSoft),
            title: Text(tr('forward'), style: TextStyle(color: p.text)),
            onTap: () => Navigator.pop(ctx, EntryAction.forward),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: p.danger),
            title: Text(tr('delete'), style: TextStyle(color: p.danger)),
            onTap: () => Navigator.pop(ctx, EntryAction.delete),
          ),
        ],
      ),
    ),
  );
}

Future<Chat?> showForwardDialog(BuildContext context, AppModel model) {
  final p = model.p;
  final tr = model.tr;
  return showDialog<Chat>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: p.modalBg,
      title: Text(tr('forward_to'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
      children: [
        for (final c in model.state.chats)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, c),
            child: Row(
              children: [
                ChatAvatar(chat: c, size: 34, iconSize: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text)),
                ),
              ],
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('cancel'), style: TextStyle(color: p.textSoft)),
        ),
      ],
    ),
  );
}

Future<List<TodoItem>?> showTodoEditorDialog(
    BuildContext context, AppModel model, {Entry? entry}) async {
  final p = model.p;
  final tr = model.tr;
  final items = <TodoItem>[
    if (entry != null) ...entry.items!.map((i) => TodoItem(id: i.id, text: i.text, done: i.done)),
  ];
  final field = TextEditingController();

  return showDialog<List<TodoItem>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(tr(entry != null ? 'todo_edit_title' : 'todo_new_title'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: field,
                      style: TextStyle(color: p.text, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: tr('todo_item_hint'),
                        hintStyle: TextStyle(color: p.textFaint, fontSize: 13.5),
                        isDense: true,
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.divider)),
                        focusedBorder:
                            UnderlineInputBorder(borderSide: BorderSide(color: p.accent)),
                      ),
                      onSubmitted: (_) => setState(() {
                        final t = field.text.trim();
                        if (t.isNotEmpty) {
                          items.add(TodoItem(id: uid('t'), text: t));
                          field.clear();
                        }
                      }),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle, color: p.accent),
                    onPressed: () => setState(() {
                      final t = field.text.trim();
                      if (t.isNotEmpty) {
                        items.add(TodoItem(id: uid('t'), text: t));
                        field.clear();
                      }
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 200,
                decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(8)),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => ListTile(
                    dense: true,
                    leading: Icon(Icons.checklist, size: 18, color: p.textSoft),
                    title: Text(items[i].text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: p.text)),
                    trailing: IconButton(
                      icon: Icon(Icons.close, size: 18, color: p.textFaint),
                      onPressed: () => setState(() => items.removeAt(i)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('cancel'), style: TextStyle(color: p.textSoft))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            onPressed: () {
              final cleaned = items.where((i) => i.text.trim().isNotEmpty).toList();
              if (cleaned.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('todo_empty'))));
                return;
              }
              Navigator.pop(ctx, cleaned);
            },
            child: Text(tr('todo_done')),
          ),
        ],
      ),
    ),
  );
}

Future<DateTime?> showReminderPicker(BuildContext context, AppModel model) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now.add(const Duration(minutes: 5)),
    firstDate: now,
    lastDate: now.add(const Duration(days: 365 * 2)),
  );
  if (date == null) return null;
  if (!context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

enum SendOption { later, daily, weekly, custom }

enum AttachOption { photo, todo }

Future<AttachOption?> showAttachMenuPopup(
    BuildContext context, AppModel model, Offset globalPos) {
  final p = model.p;
  final tr = model.tr;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<AttachOption>(
    context: context,
    color: p.modalBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(value: AttachOption.photo, child: Row(children: [Icon(Icons.photo_outlined, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr('attach_photo'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: AttachOption.todo, child: Row(children: [Icon(Icons.checklist, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr('attach_todo'), style: TextStyle(color: p.text))])),
    ],
  );
}

enum ChatTopAction { remind, edit, delete, toggleHide, toggleNotifications, search }

Future<ChatTopAction?> showChatTopMenuPopup(
    BuildContext context, AppModel model) {
  final p = model.p;
  final tr = model.tr;
  return showMenu<ChatTopAction>(
    context: context,
    color: p.modalBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    position: const RelativeRect.fromLTRB(1000, 0, 0, 0),
    items: [
      PopupMenuItem(value: ChatTopAction.remind, child: Row(children: [Icon(Icons.alarm, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr('remind'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: ChatTopAction.edit, child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(tr('edit_chat'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: ChatTopAction.delete, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: p.danger), const SizedBox(width: 10), Text(tr('delete'), style: TextStyle(color: p.danger))])),
    ],
  );
}

/// Multi-select weekday picker. Returns selected weekdays (1=Mon..7=Sun).
Future<List<int>?> showWeekdayPickerDialog(
    BuildContext context, AppModel model, List<int> initial) {
  final p = model.p;
  final tr = model.tr;
  final names = tr('weekdays_short').split(' ');
  final selected = Set<int>.of(initial);
  return showDialog<List<int>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(tr('send_weekly'), style: TextStyle(color: p.text)),
        content: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(names[d - 1]),
                selected: selected.contains(d),
                onSelected: (v) => setState(() => v ? selected.add(d) : selected.remove(d)),
                labelStyle: TextStyle(color: selected.contains(d) ? Colors.white : p.textSoft),
                selectedColor: p.accent,
                checkmarkColor: Colors.white,
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('close'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, selected.toList()..sort()),
            child: Text(tr('todo_done')),
          ),
        ],
      ),
    ),
  );
}

Future<String?> showFolderNameDialog(
  BuildContext context,
  AppModel model, {
  String? initial,
}) {
  final p = model.p;
  final tr = model.tr;
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.modalBg,
      title: Text(tr(initial == null ? 'new_folder' : 'edit_folder'),
          style: TextStyle(color: p.text)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: TextStyle(color: p.text),
        decoration: InputDecoration(
          hintText: tr('folder_name_hint'),
          hintStyle: TextStyle(color: p.textFaint),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('close'))),
        TextButton(
          onPressed: () {
            final name = ctrl.text.trim();
            Navigator.pop(ctx, name.isEmpty ? null : name);
          },
          child: Text(tr('todo_done')),
        ),
      ],
    ),
  );
}

enum ChatAction { pin, unpin, moveToFolder, edit, delete }

Future<ChatAction?> showChatCtxPopup(BuildContext context, AppModel model, Chat chat, Offset globalPos) {
  final p = model.p;
  final tr = model.tr;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<ChatAction>(
    context: context,
    color: p.modalBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    position: RelativeRect.fromRect(Rect.fromPoints(globalPos, globalPos), Offset.zero & overlay.size),
    items: [
      PopupMenuItem(value: chat.pinned ? ChatAction.unpin : ChatAction.pin, child: Row(children: [Icon(Icons.push_pin, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr(chat.pinned ? 'unpin' : 'pin'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: ChatAction.moveToFolder, child: Row(children: [Icon(Icons.folder_copy_outlined, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr('move_to_folder'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: ChatAction.edit, child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(tr('edit'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: ChatAction.delete, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), const SizedBox(width: 10), Text(tr('delete'), style: TextStyle(color: Colors.redAccent))])),
    ],
  );
}

Future<ChatAction?> showChatCtxSheet(BuildContext context, AppModel model, Chat chat) {
  final p = model.p;
  final tr = model.tr;
  Widget tile(IconData icon, String label, ChatAction action, {Color? color}) => ListTile(
        leading: Icon(icon, color: color ?? p.accent),
        title: Text(label, style: TextStyle(fontSize: 15, color: color ?? p.text)),
        onTap: () => Navigator.pop(context, action),
      );
  return showModalBottomSheet<ChatAction>(
    context: context,
    backgroundColor: p.modalBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          tile(
            Icons.push_pin,
            tr(chat.pinned ? 'unpin' : 'pin'),
            chat.pinned ? ChatAction.unpin : ChatAction.pin,
          ),
          tile(Icons.folder_copy_outlined, tr('move_to_folder'), ChatAction.moveToFolder),
          tile(Icons.edit_outlined, tr('edit'), ChatAction.edit),
          tile(Icons.delete_outline, tr('delete'), ChatAction.delete, color: Colors.redAccent),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<String?> showMoveToFolderPopup(BuildContext context, AppModel model, Offset globalPos) {
  final p = model.p;
  final tr = model.tr;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<String>(
    context: context,
    color: p.modalBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    position: RelativeRect.fromRect(Rect.fromPoints(globalPos, globalPos), Offset.zero & overlay.size),
    items: [
      PopupMenuItem(value: '', child: Row(children: [Icon(Icons.folder_off_outlined, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr('no_folder'), style: TextStyle(color: p.text))])),
      for (final f in model.state.folders) PopupMenuItem(value: f.id, child: Row(children: [Icon(Icons.folder_outlined, size: 18, color: p.accent), const SizedBox(width: 10), Text(f.name, style: TextStyle(color: p.text))])),
    ],
  );
}

/// Returns folder id, empty string for "no folder", null to cancel.
Future<String?> showMoveToFolderSheet(BuildContext context, AppModel model) {
  final p = model.p;
  final tr = model.tr;
  Widget tile(String? folderId, String label, IconData icon) => ListTile(
        leading: Icon(icon, color: p.accent),
        title: Text(label, style: TextStyle(fontSize: 15, color: p.text)),
        onTap: () => Navigator.pop(context, folderId ?? ''),
      );
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.modalBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          tile(null, tr('no_folder'), Icons.folder_off_outlined),
          for (final f in model.state.folders)
            tile(f.id, f.name, Icons.folder_outlined),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
