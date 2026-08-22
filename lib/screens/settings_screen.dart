import 'dart:io';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../src/app_model.dart';
import '../src/backup.dart';
import '../src/i18n.dart';
import '../src/rss.dart';
import '../src/theme.dart';
import 'widget_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _cacheMaxGb = 1024; // 0 = ∞, in MB (1024=1GB)

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
    _loadCachePref();
  }

  Future<void> _loadCachePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var cache = prefs.getInt('tn-cache-max-gb') ?? 1024;
      if (![1024, 3072, 5120, 0].contains(cache)) cache = 1024;
      if (mounted) setState(() => _cacheMaxGb = cache);
    } catch (_) {}
  }

  Future<void> _saveCacheMax(int v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tn-cache-max-gb', v);
      if (mounted) setState(() => _cacheMaxGb = v);
    } catch (_) {}
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
            child: Column(
              children: [
                Row(
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
                const Divider(height: 24, color: Color(0xFF2A3441)),
                Align(alignment: Alignment.centerLeft, child: Text('Максимальный размер кэша', style: TextStyle(color: p.accent, fontSize: 14, fontWeight: FontWeight.w600))),
                const SizedBox(height: 4),
                Text('Только картинки каналов, заметки хранятся всегда', style: TextStyle(color: p.textFaint, fontSize: 11)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final v in [1024, 3072, 5120, 0])
                      Text(v == 0 ? '∞' : v >= 1024 ? '${v ~/ 1024} GB' : '$v MB', style: TextStyle(color: _cacheMaxGb == v ? p.accent : p.textFaint, fontSize: 13, fontWeight: _cacheMaxGb == v ? FontWeight.w700 : FontWeight.w400)),
                  ],
                ),
                Slider(
                  value: [1024, 3072, 5120, 0].indexOf(_cacheMaxGb).clamp(0, 3).toDouble(),
                  min: 0,
                  max: 3,
                  divisions: 3,
                  activeColor: p.accent,
                  inactiveColor: p.divider,
                  thumbColor: p.accent,
                  onChanged: (v) => setState(() => _cacheMaxGb = [1024, 3072, 5120, 0][v.round()]),
                  onChangeEnd: (v) => _saveCacheMax([1024, 3072, 5120, 0][v.round()]),
                ),
                Text('Для RSS и медиа', style: TextStyle(fontSize: 11, color: p.textFaint)),
              ],
            ),
          ),
          _sectionLabel(tr('section_widget'), p),
          _card(
            p,
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => WidgetSettingsScreen(model: model)),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr('widget_settings_title'),
                        style: TextStyle(fontSize: 14.5, color: p.text)),
                  ),
                  Icon(Icons.chevron_right, color: p.textFaint),
                ],
              ),
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
          opt('System', 'system'),
        ],
      ),
    );
  }

}