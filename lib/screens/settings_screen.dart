import 'dart:io';

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/backup.dart';
import '../src/i18n.dart';
import '../src/rss.dart';
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

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final p = model.p;
    final tr = model.tr;

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
          _sectionLabel('RSS каналы', p),
          _card(
            p,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Кеш каналов', style: TextStyle(fontSize: 14.5, color: p.text)),
                TextButton(
                  onPressed: () async {
                    await RssService.clearCache();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Кеш очищен')));
                  },
                  child: Text('Очистить', style: TextStyle(color: p.accent)),
                ),
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

}