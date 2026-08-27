import 'package:flutter/material.dart';

import 'app_model.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

enum EntryAction { schedTime, copy, edit, forward, delete, select, share, download, pin }

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

Future<EntryAction?> showEntryCtxPopup(BuildContext context, AppModel model, Entry entry, Offset globalPos, {String chatKind = 'note'}) {
  final p = model.p;
  final tr = model.tr;
  final canEdit = entry.type == 'text' || entry.type == 'todo';
  final isImage = entry.type == 'image';
  final showSchedule = chatKind == 'tasks';
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<EntryAction>(
    context: context,
    color: p.modalBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    position: RelativeRect.fromRect(Rect.fromPoints(globalPos, globalPos), Offset.zero & overlay.size),
    items: [
      if (showSchedule) PopupMenuItem(value: EntryAction.schedTime, child: Row(children: [Icon(Icons.schedule_outlined, size: 18, color: p.accent), const SizedBox(width: 10), Text(tr('change_time'), style: TextStyle(color: p.text))])),
      PopupMenuItem(value: EntryAction.pin, child: Row(children: [Icon(Icons.push_pin_outlined, size: 18, color: entry.pinned ? p.accent : p.textSoft), const SizedBox(width: 10), Text(tr(entry.pinned ? 'unpin' : 'pin'), style: TextStyle(color: p.text))])),
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
          ListTile(
            leading: Icon(Icons.schedule_outlined, color: p.accent),
            title: Text(tr('change_time'), style: TextStyle(color: p.text)),
            onTap: () => Navigator.pop(ctx, EntryAction.schedTime),
          ),
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

Future<Chat?> showForwardDialog(BuildContext context, AppModel model,
    {bool allowNewChat = false}) {
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
        if (allowNewChat)
          SimpleDialogOption(
            onPressed: () async {
              final name = await showFolderNameDialog(ctx, model, titleKey: 'new_chat');
              if (name == null || name.trim().isEmpty) return;
              final color = appColors[model.state.chats.length % appColors.length];
              final chat = Chat(
                id: uid('c'),
                name: name.trim(),
                color: color,
                kind: 'note',
              );
              model.state.chats.add(chat);
              await model.save();
              if (ctx.mounted) Navigator.pop(ctx, chat);
            },
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, size: 30, color: p.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('new_chat'),
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w600)),
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
    if (entry != null)
      ...entry.items!.map((i) => TodoItem(
          id: i.id,
          text: i.text,
          done: i.done,
          parentId: i.parentId,
          priority: i.priority)),
  ];
  final field = TextEditingController();
  String? addUnder;

  // Index right after the last descendant of parentId — keeps subtasks
  // visually grouped under their parent in list order.
  int insertAfterSubtree(List<TodoItem> list, String? parentId) {
    if (parentId == null) return list.length;
    var idx = list.indexWhere((i) => i.id == parentId);
    if (idx < 0) return list.length;
    final ids = {parentId};
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = idx + 1; i < list.length; i++) {
        if (ids.contains(list[i].parentId)) {
          ids.add(list[i].id);
          idx = i;
          changed = true;
        }
      }
    }
    return idx + 1;
  }

  return showDialog<List<TodoItem>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void addItem() {
          final t = field.text.trim();
          if (t.isEmpty) return;
          items.insert(insertAfterSubtree(items, addUnder),
              TodoItem(id: uid('t'), text: t, parentId: addUnder));
          field.clear();
          setState(() => addUnder = null);
        }

        Future<void> rename(TodoItem it) async {
          final c = TextEditingController(text: it.text);
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (c2) => AlertDialog(
              backgroundColor: p.modalBg,
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              content: TextField(
                controller: c,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                style: TextStyle(color: p.text, fontSize: 14),
                onSubmitted: (_) => Navigator.pop(c2, true),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c2),
                    child:
                        Text(tr('cancel'), style: TextStyle(color: p.textSoft))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  onPressed: () => Navigator.pop(c2, true),
                  child: Text(tr('save')),
                ),
              ],
            ),
          );
          if (ok == true && c.text.trim().isNotEmpty) {
            setState(() => it.text = c.text.trim());
          }
        }

        // Ordered display pass: roots first, then each item's subtasks.
        final display = <MapEntry<TodoItem, int>>[];
        final byParent = <String?, List<TodoItem>>{};
        for (final it in items) {
          byParent.putIfAbsent(it.parentId, () => []).add(it);
        }
        void walk(String? parent, int d) {
          for (final it in byParent[parent] ?? const <TodoItem>[]) {
            display.add(MapEntry(it, d));
            walk(it.id, d + 1);
          }
        }

        walk(null, 0);

        Widget circle(bool done, {double size = 17}) => AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? p.accent : Colors.transparent,
                border: Border.all(
                    color: done ? p.accent : p.textFaint.withValues(alpha: .55),
                    width: 2),
              ),
              child: done ? Icon(Icons.check, size: 12, color: Colors.white) : null,
            );

        return AlertDialog(
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
                          hintText: tr(addUnder != null ? 'todo_sub_hint' : 'todo_item_hint'),
                          hintStyle: TextStyle(color: p.textFaint, fontSize: 13.5),
                          isDense: true,
                          enabledBorder:
                              UnderlineInputBorder(borderSide: BorderSide(color: p.divider)),
                          focusedBorder:
                              UnderlineInputBorder(borderSide: BorderSide(color: p.accent)),
                        ),
                        onSubmitted: (_) => addItem(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle, color: p.accent),
                      onPressed: addItem,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 220,
                  decoration:
                      BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(8)),
                  child: ListView.builder(
                    itemCount: display.length,
                    itemBuilder: (ctx, i) {
                      final me = display[i];
                      final it = me.key;
                      final depth = me.value;
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.only(left: 8.0 + depth * 18.0, right: 2),
                        leading: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            toggleTodoCascade(items, it.id);
                            setState(() {});
                          },
                          child: Padding(padding: const EdgeInsets.all(3), child: circle(it.done)),
                        ),
                        title: InkWell(
                          onTap: () => rename(it),
                          child: Text(it.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: it.done ? p.textFaint : p.text,
                                decoration: it.done ? TextDecoration.lineThrough : null,
                                decorationColor: p.textFaint,
                              )),
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (depth == 0)
                            InkWell(
                              onTap: () => setState(() => addUnder = it.id),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.subdirectory_arrow_right,
                                    size: 15, color: p.textFaint),
                              ),
                            ),
                          InkWell(
                            onTap: () {
                              removeTodoItem(items, it.id);
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 16, color: p.textFaint),
                            ),
                          ),
                        ]),
                      );
                    },
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
                final cleaned =
                    items.where((i) => i.text.trim().isNotEmpty).toList();
                if (cleaned.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('todo_empty'))));
                  return;
                }
                Navigator.pop(ctx, cleaned);
              },
              child: Text(tr('todo_done')),
            ),
          ],
        );
      },
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

enum SendOption { later, daily, weekdays, weekly, monthly }

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

enum ChatTopAction { remind, edit, delete, toggleHide, toggleNotifications, search, export }

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

/// Day-of-month picker for monthly recurring tasks. Returns 1..31.
Future<int?> showMonthDayPickerDialog(
    BuildContext context, AppModel model,
    {int? initial}) {
  final p = model.p;
  var selected = initial ?? DateTime.now().day;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(model.tr('sched_monthly_day'), style: TextStyle(color: p.text)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.count(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1,
            shrinkWrap: true,
            children: [
              for (var d = 1; d <= 31; d++)
                InkWell(
                  onTap: () => Navigator.pop(ctx, d),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          d == selected ? p.accent.withValues(alpha: .25) : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color:
                              d == selected ? p.accent : p.textFaint.withValues(alpha: .4)),
                    ),
                    alignment: Alignment.center,
                    child: Text('$d',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                d == selected ? FontWeight.w700 : FontWeight.w400,
                            color: p.text)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(model.tr('close'))),
        ],
      ),
    ),
  );
}

class SchedulePick {
  final int? dueAt;
  final String? recurrence;
  final List<int>? recurrenceDays;
  final int? monthDay;
  final int priority;
  const SchedulePick(
      {this.dueAt, this.recurrence, this.recurrenceDays, this.monthDay, this.priority = 0});
}

/// Aligns the first occurrence of a recurring rule with the chosen days.
DateTime alignFirstOccurrence(DateTime cur, String? rec, List<int>? days, int? monthDay) {
  var cand = DateTime(cur.year, cur.month, cur.day, cur.hour, cur.minute);
  if (rec == 'weekly' && days != null && days.isNotEmpty) {
    while (!days.contains(cand.weekday)) {
      cand = cand.add(const Duration(days: 1));
    }
  } else if (rec == 'monthly' && monthDay != null && cand.day != monthDay) {
    int clampDom(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return monthDay > last ? last : monthDay;
    }

    var c = DateTime(cand.year, cand.month, clampDom(cand.year, cand.month), cand.hour, cand.minute);
    if (!c.isAfter(cand)) {
      var y = cand.year;
      var m = cand.month + 1;
      if (m > 12) {
        m = 1;
        y++;
      }
      c = DateTime(y, m, clampDom(y, m), cand.hour, cand.minute);
    }
    cand = c;
  }
  return cand;
}

/// Unified scheduling sheet: date + time + recurrence presets together.
/// Used for long-press send / attach-todo AND for editing an existing
/// entry's schedule ("change time"), so presets are never lost.
Future<SchedulePick?> showScheduleSheet(
  BuildContext context,
  AppModel model, {
  int? initialDueAt,
  String? initialRecurrence,
  List<int>? initialRecurrenceDays,
  int? initialMonthDay,
  int initialPriority = 0,
  bool showPriority = false,
}) {
  final p = model.p;
  final tr = model.tr;
  DateTime dt = initialDueAt != null
      ? DateTime.fromMillisecondsSinceEpoch(initialDueAt)
      : DateTime.now().add(const Duration(hours: 1));
  String? rec = initialRecurrence;
  List<int> days = List.of(initialRecurrenceDays ?? const <int>[]);
  int md = initialMonthDay ?? dt.day;
  var priority = initialPriority;

  bool sel(String v) {
    switch (v) {
      case 'once':
        return rec == null;
      case 'daily':
        return rec == 'daily';
      case 'weekdays':
        return rec == 'weekly' &&
            days.length == 5 &&
            days.every((d) => d >= 1 && d <= 5);
      case 'pickdays':
        return rec == 'weekly' && !(days.length == 5 && days.every((d) => d >= 1 && d <= 5));
      case 'monthly':
        return rec == 'monthly';
    }
    return false;
  }

  String two(int v) => v.toString().padLeft(2, '0');

  Future<void> editDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (d == null) return;
    dt = DateTime(d.year, d.month, d.day, dt.hour, dt.minute);
  }

  Future<void> editTime() async {
    // Numeric entry mode: the round dial mis-taps on many Samsung skins.
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dt),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (t == null) return;
    dt = DateTime(dt.year, dt.month, dt.day, t.hour, t.minute);
  }

  return showModalBottomSheet<SchedulePick>(
    context: context,
    backgroundColor: p.modalBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        top: false,
        child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: p.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 10),
            Text(tr('sched_sheet_title'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (v, key) in [
                  ('once', 'sched_once'),
                  ('daily', 'sched_daily'),
                  ('weekdays', 'sched_weekdays'),
                  ('pickdays', 'sched_pick_days'),
                  ('monthly', 'sched_monthly'),
                ])
                  ChoiceChip(
                    label: Text(tr(key)),
                    selected: sel(v),
                    onSelected: (_) async {
                      switch (v) {
                        case 'once':
                          setSheet(() => rec = null);
                          break;
                        case 'daily':
                          setSheet(() => rec = 'daily');
                          break;
                        case 'weekdays':
                          setSheet(() {
                            rec = 'weekly';
                            days = [1, 2, 3, 4, 5];
                          });
                          break;
                        case 'pickdays':
                          final d = await showWeekdayPickerDialog(ctx, model, days);
                          if (d != null && d.isNotEmpty) {
                            setSheet(() {
                              rec = 'weekly';
                              days = d;
                            });
                          }
                          break;
                        case 'monthly':
                          final m = await showMonthDayPickerDialog(ctx, model, initial: md);
                          if (m != null) {
                            setSheet(() {
                              rec = 'monthly';
                              md = m;
                            });
                          }
                          break;
                      }
                    },
                    selectedColor: p.accent,
                    backgroundColor: p.bgChat,
                    labelStyle: TextStyle(
                        color: sel(v) ? Colors.white : p.textSoft,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5),
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: sel(v) ? p.accent : p.divider)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.event_outlined, size: 18, color: p.accent),
                    label: Text('${two(dt.day)}.${two(dt.month)}.${dt.year}',
                        style: TextStyle(color: p.text)),
                    onPressed: () async {
                      await editDate();
                      setSheet(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.schedule_outlined, size: 18, color: p.accent),
                    label: Text('${two(dt.hour)}:${two(dt.minute)}',
                        style: TextStyle(color: p.text)),
                    onPressed: () async {
                      await editTime();
                      setSheet(() {});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final h in [7, 9, 12, 13, 15, 17, 19, 21])
                  GestureDetector(
                    onTap: () => setSheet(() {
                      dt = DateTime(dt.year, dt.month, dt.day, h, 0);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: dt.hour == h && dt.minute == 0
                            ? p.accent.withValues(alpha: .18)
                            : p.bgChat,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: dt.hour == h && dt.minute == 0
                              ? p.accent
                              : p.divider,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        '${two(h)}:00',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: dt.hour == h && dt.minute == 0
                              ? p.accent
                              : p.textSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (rec != null) ...[
              const SizedBox(height: 8),
              Text(
                rec == 'daily'
                    ? tr('sched_daily')
                    : rec == 'weekly'
                        ? '${tr('sched_weekdays_short')}: ${days.map((d) => tr('weekdays_short').split(' ')[d - 1]).join(', ')}'
                        : '${tr('sched_monthly')} $md',
                style: TextStyle(fontSize: 11.5, color: p.textFaint),
              ),
            ],
            if (showPriority) ...[
              const SizedBox(height: 14),
              Text(tr('priority'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.textFaint,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Row(children: [
                for (final pr in [0, 1, 2])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: priority == pr,
                      onSelected: (_) => setSheet(() => priority = pr),
                      label: Text(tr('priority_$pr'),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: priority == pr ? Colors.white : p.textSoft,
                              fontWeight: FontWeight.w600)),
                      selectedColor: p.priority(pr),
                      backgroundColor: p.bgChat,
                      checkmarkColor: Colors.white,
                      side: BorderSide(
                          color: priority == pr ? p.priority(pr) : p.divider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('close'), style: TextStyle(color: p.textSoft)),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  onPressed: () {
                    final aligned = alignFirstOccurrence(dt, rec, days, md);
                    Navigator.pop(
                      ctx,
                      SchedulePick(
                        dueAt: aligned.millisecondsSinceEpoch,
                        recurrence: rec,
                        recurrenceDays: rec == 'weekly' ? List.of(days) : null,
                        monthDay: rec == 'monthly' ? md : null,
                        priority: priority,
                      ),
                    );
                  },
                   child: Text(tr('todo_done')),
                 ),
               ],
              ),
           ],
         ),
       ),
       ),
     ),
   );
 }

 Future<String?> showFolderNameDialog(
  BuildContext context,
  AppModel model, {
  String? initial,
  String? titleKey,
}) {
  final p = model.p;
  final tr = model.tr;
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.modalBg,
      title: Text(tr(titleKey ?? (initial == null ? 'new_folder' : 'edit_folder')),
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

/// Create or edit a folder: name + accent color. Returns the folder, or
/// null when cancelled. Pass [folder] to edit an existing one.
Future<Folder?> showFolderEditDialog(
  BuildContext context,
  AppModel model, {
  Folder? folder,
}) {
  final p = model.p;
  final tr = model.tr;
  final ctrl = TextEditingController(text: folder?.name ?? '');
  var selectedColor = folder?.color;
  return showDialog<Folder>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(tr(folder == null ? 'new_folder' : 'edit_folder'),
            style: TextStyle(color: p.text)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(color: p.text),
                decoration: InputDecoration(
                  hintText: tr('folder_name_hint'),
                  hintStyle: TextStyle(color: p.textFaint),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.divider)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.accent)),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('color'),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                            ? Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              final result = folder ?? Folder(id: uid('f'), name: name);
              result
                ..name = name
                ..color = selectedColor;
              Navigator.pop(ctx, result);
            },
            child: Text(tr(folder == null ? 'create' : 'save')),
          ),
        ],
      ),
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
