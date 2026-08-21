import 'package:flutter/material.dart';

import 'app_model.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

enum EntryAction { copy, edit, forward, delete, cancelSchedule }

Future<Chat?> showChatEditDialog(BuildContext context, AppModel model, {Chat? chat}) async {
  final p = model.p;
  final tr = model.tr;
  final nameField = TextEditingController(text: chat?.name ?? '');
  var selectedIcon = chat?.icon;
  var selectedColor = chat?.color ?? appColors[0];

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
                Text(tr('icon'),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                const SizedBox(height: 6),
                Wrap(
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
              final result = chat ?? Chat(id: uid('c'), name: name, color: selectedColor);
              result
                ..name = name
                ..icon = selectedIcon
                ..color = selectedColor;
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
          if (entry.isScheduled)
            ListTile(
              leading: Icon(Icons.schedule, color: p.danger),
              title: Text(tr('cancel_schedule'), style: TextStyle(color: p.danger)),
              onTap: () => Navigator.pop(ctx, EntryAction.cancelSchedule),
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