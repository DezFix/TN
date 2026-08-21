import 'dart:io';

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/backup.dart';
import '../src/i18n.dart';
import '../src/models.dart';
import '../src/reminders.dart';
import '../src/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    super.dispose();
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  Future<void> _removeReminder(String id) async {
    Reminder? r;
    for (final x in widget.model.state.reminders) {
      if (x.id == id) {
        r = x;
        break;
      }
    }
    if (r == null) return;
    await RemindersService.instance.cancel(r);
    widget.model.state.reminders.removeWhere((x) => x.id == id);
    await widget.model.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final p = model.p;
    final tr = model.tr;
    final reminders = model.state.reminders.toList()
      ..sort((a, b) => a.when.compareTo(b.when));

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(tr('settings'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _sectionLabel(tr('section_appearance'), p),
          _card(
            p,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('theme'),
                    style: TextStyle(fontSize: 14.5, color: p.text)),
                _themeToggle(p, model.state.theme),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(tr('chat_hint'),
              style: TextStyle(fontSize: 12, color: p.textFaint)),
          _sectionLabel(tr('section_language'), p),
          _card(
            p,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (code, label) in appLanguages)
                  GestureDetector(
                    onTap: () => model.setLang(code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: model.state.lang == code
                            ? p.accent
                            : p.bgChat,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: model.state.lang == code ? Colors.white : p.textSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _sectionLabel(tr('section_reminders'), p),
          if (reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(tr('remind_empty'),
                  style: TextStyle(fontSize: 13, color: p.textFaint)),
            )
          else
            for (final r in reminders) _reminderRow(model, r, tr),
          _sectionLabel(tr('section_backup'), p),
          _card(
            p,
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: FilledButton.icon(icon: const Icon(Icons.upload, size: 18), style: FilledButton.styleFrom(backgroundColor: p.accent), label: Text(tr('backup_export')), onPressed: () async { try { final path = await BackupService.export(model.state); if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('backup_exported', [path])))); } catch (_) { if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('backup_error')))); } })),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(icon: Icon(Icons.download, size: 18, color: p.text), label: Text(tr('backup_import'), style: TextStyle(color: p.text)), onPressed: () async { final files = await BackupService.listBackups(); if (!context.mounted) return; if (files.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('backup_error')))); return; } final picked = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(backgroundColor: p.modalBg, title: Text(tr('backup_import'), style: TextStyle(color: p.text)), children: [for (final f in files.take(20)) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, f.path), child: Text(f.path.split('/').last, style: TextStyle(color: p.text, fontSize: 13))), SimpleDialogOption(onPressed: () => Navigator.pop(ctx), child: Text(tr('close'), style: TextStyle(color: p.textSoft)))]));                   if (picked == null) return; try { final file = File(picked); await BackupService.importFrom(file, model.state); model.tr = makeTranslator(model.state.lang); model.refresh(); if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('backup_imported')))); setState(() {}); } catch (_) { if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('backup_error')))); } })),
                ]),
                const SizedBox(height: 8),
                Text(tr('backup_soon'), style: TextStyle(fontSize: 11.5, color: p.textFaint)),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, Palette p) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.textFaint)),
      );

  Widget _card(Palette p, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: p.bgChat,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _themeToggle(Palette p, String current) {
    Widget opt(String label, String value) => GestureDetector(
          onTap: () => widget.model.setTheme(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: current == value ? p.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: current == value ? Colors.white : p.textSoft,
                )),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          opt(widget.model.tr('light'), 'light'),
          opt(widget.model.tr('dark'), 'dark'),
        ],
      ),
    );
  }

  Widget _reminderRow(AppModel model, Reminder r, String Function(String) tr) {
    final p = model.p;
    final chat = model.state.chatById(r.chatId);
    final dt = DateTime.fromMillisecondsSinceEpoch(r.when).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.bgChat,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.alarm, color: p.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat?.name ?? r.chatId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                Text(when, style: TextStyle(fontSize: 12.5, color: p.textSoft)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: p.textFaint, size: 20),
            onPressed: () => _removeReminder(r.id),
          ),
        ],
      ),
    );
  }
}