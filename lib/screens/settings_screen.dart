import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../src/app_model.dart';
import '../src/dialogs.dart';
import '../src/i18n.dart';
import '../src/models.dart';
import '../src/rss.dart';
import '../src/theme.dart';
import 'backup_screen.dart';
import 'folders_edit_screen.dart';
import 'tags_screen.dart';
import 'trash_screen.dart';
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
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BackupScreen(model: model))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Icon(Icons.settings_backup_restore, size: 20, color: p.accent),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tr('backup_open'), style: TextStyle(fontSize: 14.5, color: p.text))),
                      Icon(Icons.chevron_right, size: 20, color: p.textFaint),
                    ]),
                  ),
                ),
                Divider(height: 20, color: p.divider),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrashScreen(model: model))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 20, color: p.danger),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tr('trash'), style: TextStyle(fontSize: 14.5, color: p.text))),
                      if (model.state.chats.any((c) => c.isTrashed))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                          child: Text('${model.state.chats.where((c) => c.isTrashed).length}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.danger)),
                        ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, size: 20, color: p.textFaint),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          _sectionLabel(tr('rss_channels'), p),
          _card(
            p,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr('rss_cache_channels'), style: TextStyle(fontSize: 14.5, color: p.text)),
                    TextButton(
                      onPressed: () async {
                        await RssService.clearCache();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('rss_cache_cleared'))));
                      },
                      child: Text(tr('rss_clear'), style: TextStyle(color: p.accent)),
                    ),
                  ],
                ),
                Divider(height: 24, color: p.divider),
                Align(alignment: Alignment.centerLeft, child: Text(tr('rss_cache_max_size'), style: TextStyle(color: p.accent, fontSize: 14, fontWeight: FontWeight.w600))),
                const SizedBox(height: 4),
                Text(tr('rss_cache_hint'), style: TextStyle(color: p.textFaint, fontSize: 11)),
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
                Text(tr('rss_cache_for'), style: TextStyle(fontSize: 11, color: p.textFaint)),
              ],
            ),
          ),
          _sectionLabel(tr('folders'), p),
          _card(
            p,
            child: Column(
              children: [
                InkWell(
                  onTap: () async {
                    final name = await showFolderNameDialog(context, model);
                    if (name == null) return;
                    model.state.folders.add(Folder(id: uid('f'), name: name));
                    await model.save();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('folder_created', [name]))));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Icon(Icons.create_new_folder_outlined, size: 20, color: p.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('new_folder'),
                            style: TextStyle(fontSize: 14.5, color: p.text)),
                      ),
                    ],
                  ),
                ),
                Divider(height: 20, color: p.divider),
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TagsScreen(model: model)),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Icon(Icons.tag, size: 20, color: p.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('tags_title'),
                            style: TextStyle(fontSize: 14.5, color: p.text)),
                      ),
                      Icon(Icons.chevron_right, color: p.textFaint),
                    ],
                  ),
                ),
                Divider(height: 20, color: p.divider),
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FoldersEditScreen(model: model)),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Icon(Icons.swap_vert, size: 20, color: p.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('folders_reorder'),
                            style: TextStyle(fontSize: 14.5, color: p.text)),
                      ),
                      Icon(Icons.chevron_right, color: p.textFaint),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Home-screen widgets are an Android feature — hide on desktop.
          if (!Platform.isWindows) ...[
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
          ],
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