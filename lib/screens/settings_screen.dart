import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../src/app_lock.dart';
import '../src/app_update.dart' show appBuildVersion;
import '../src/app_model.dart';
import '../src/media.dart';
import 'about_screen.dart';
import 'lock_settings_screen.dart';
import '../src/dialogs.dart';
import '../src/i18n.dart';
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
  bool _lockOn = false;
  String _methodKey = 'biometric';
  bool _cacheLoading = true;
  int _cacheMedia = 0, _cacheTrash = 0, _cacheTemp = 0, _cacheTotal = 0;
  bool _smartTasks = true;
  bool _smartNotes = true;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
    _loadCachePref();
    _loadLockPref();
    _loadCacheSize();
    _loadSmartFolders();
  }

  Future<void> _loadSmartFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _smartTasks = prefs.getBool('tn-smartfolder-tasks') ?? true;
        _smartNotes = prefs.getBool('tn-smartfolder-notes') ?? true;
      });
    } catch (_) {}
  }

  Future<void> _setSmartFolder(String kind, bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kind == 'tasks' ? 'tn-smartfolder-tasks' : 'tn-smartfolder-notes', v);
      if (mounted) setState(() => kind == 'tasks' ? _smartTasks = v : _smartNotes = v);
    } catch (_) {}
  }

  Future<void> _loadCacheSize() async {
    setState(() => _cacheLoading = true);
    try {
      final s = await MediaStore().cacheStats();
      if (!mounted) return;
      setState(() {
        _cacheMedia = s.media;
        _cacheTrash = s.trash;
        _cacheTemp = s.temp;
        _cacheTotal = s.total;
        _cacheLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cacheLoading = false);
    }
  }

  Future<void> _clearCacheTrash() async {
    final n = await MediaStore().clearTrashAndTemp();
    await _loadCacheSize();
    if (!mounted) return;
    final tr = widget.model.tr;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('cache_cleared', [humanBytes(_cacheTrash + _cacheTemp)]))),
    );
  }

  Future<void> _loadLockPref() async {
    final v = await AppLock.isEnabled();
    var methodKey = 'biometric';
    if (v) {
      final methods = await AppLock.getEnabledMethods();
      if (methods.length > 1) {
        methodKey = 'methods_multi';
      } else if (methods.contains(LockMethod.pattern)) {
        methodKey = 'pattern';
      } else if (methods.contains(LockMethod.pin)) {
        methodKey = 'pin';
      } else {
        methodKey = 'biometric';
      }
    }
    if (mounted) setState(() => _lockOn = v);
    if (mounted) setState(() => _methodKey = methodKey);
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

  String _cacheMaxLabel(int v) =>
      v == 0 ? '∞' : v >= 1024 ? '${v ~/ 1024} GB' : '$v MB';

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
          _sectionLabel(tr('cache_section'), p),
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Общий вес кеша + мусор
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr('cache_total'),
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                    _cacheLoading
                        ? Text(tr('cache_calculating'),
                            style: TextStyle(fontSize: 13, color: p.textFaint))
                        : Text(humanBytes(_cacheTotal),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.accent)),
                  ],
                ),
                const SizedBox(height: 8),
                if (!_cacheLoading) ...[
                  _cacheRow(tr('cache_media'), _cacheMedia, p),
                  const SizedBox(height: 4),
                  _cacheRow(tr('cache_trash'), _cacheTrash, p, isTrash: true),
                  const SizedBox(height: 4),
                  _cacheRow(tr('cache_temp'), _cacheTemp, p, isTrash: true),
                ],
                const SizedBox(height: 10),
                Text(tr('cache_hint'), style: TextStyle(fontSize: 11, color: p.textFaint, height: 1.35)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: p.danger.withValues(alpha: 0.9)),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.white),
                    label: Text(tr('cache_clear'), style: const TextStyle(color: Colors.white)),
                    onPressed: (_cacheTrash + _cacheTemp) == 0 && !_cacheLoading ? null : _clearCacheTrash,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loadCacheSize,
                    child: Text(tr('rss_refresh'), style: TextStyle(color: p.accent)),
                  ),
                ),
                Divider(height: 24, color: p.divider),
                // RSS внутри той же карточки
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr('rss_cache_channels'), style: TextStyle(fontSize: 14.5, color: p.text)),
                    TextButton(
                      onPressed: () async {
                        await RssService.clearCache();
                        await _loadCacheSize();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('rss_cache_cleared'))));
                      },
                      child: Text(tr('rss_clear'), style: TextStyle(color: p.accent)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(tr('rss_cache_max_size'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: p.textFaint)),
                Slider(
                  value: [1024, 3072, 5120, 0].indexOf(_cacheMaxGb).clamp(0, 3).toDouble(),
                  min: 0,
                  max: 3,
                  divisions: 3,
                  label: _cacheMaxLabel(_cacheMaxGb),
                  activeColor: p.accent,
                  inactiveColor: p.divider,
                  thumbColor: p.accent,
                  onChanged: (v) => setState(() => _cacheMaxGb = [1024, 3072, 5120, 0][v.round()]),
                  onChangeEnd: (v) => _saveCacheMax([1024, 3072, 5120, 0][v.round()]),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(_cacheMaxLabel(_cacheMaxGb),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: p.textSoft)),
                ),
                const SizedBox(height: 4),
                Text(tr('rss_cache_hint'), style: TextStyle(fontSize: 11, color: p.textFaint)),
                const SizedBox(height: 8),
                Text(tr('rss_cache_for'), style: TextStyle(fontSize: 11, color: p.textFaint)),
                const SizedBox(height: 12),
                // Автоочистка — один переключатель на всё
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.bgList,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.divider.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_delete_outlined, size: 18, color: p.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('cache_auto_title'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                            Text(tr('cache_auto_hint'), style: TextStyle(fontSize: 11, color: p.textFaint)),
                          ],
                        ),
                      ),
                      Icon(Icons.check_circle, size: 20, color: p.accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _sectionLabel(tr('smart_folders'), p),
          _card(
            p,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 18, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('smart_folders'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.5))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(tr('smart_folders_hint'), style: TextStyle(fontSize: 11, color: p.textFaint)),
                const SizedBox(height: 10),
                _smartFolderToggle(
                  p: p,
                  icon: Icons.check_circle_outline,
                  title: tr('smart_tasks'),
                  subtitle: tr('smart_tasks_hint'),
                  value: _smartTasks,
                  onChanged: (v) => _setSmartFolder('tasks', v),
                ),
                const SizedBox(height: 8),
                _smartFolderToggle(
                  p: p,
                  icon: Icons.note_alt_outlined,
                  title: tr('smart_notes'),
                  subtitle: tr('smart_notes_hint'),
                  value: _smartNotes,
                  onChanged: (v) => _setSmartFolder('notes', v),
                ),
                const SizedBox(height: 8),
                Text(tr('smart_folders_future'), style: TextStyle(fontSize: 11, color: p.textFaint, fontStyle: FontStyle.italic)),
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
                    // Same name+color dialog as the FAB flow on the main
                    // screen — text-only here made colored folders impossible.
                    final result = await showFolderEditDialog(context, model);
                    if (result == null) return;
                    model.state.folders.add(result);
                    await model.save();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('folder_created', [result.name]))));
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
            _sectionLabel(tr('section_widget'), p),            _card(
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
          // Biometric app lock — Android/iOS only (local_auth support).
          if (AppLock.supported) ...[
            _sectionLabel(tr('lock_enable'), p),
            _card(
              p,
              child: InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => LockSettingsScreen(model: model)),
                  );
                  await _loadLockPref();
                },
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    Icon(Icons.fingerprint,
                        size: 22, color: _lockOn ? p.accent : p.textSoft),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('lock_menu'),
                              style:
                                  TextStyle(fontSize: 14.5, color: p.text)),
                          Text(tr(_lockOn
                                  ? (_methodKey == 'methods_multi'
                                      ? 'lock_methods_multi'
                                      : 'lock_method_${_methodKey}')
                                  : 'lock_hint'),
                              style: TextStyle(
                                  fontSize: 11, color: p.textFaint)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: p.textFaint),
                  ],
                ),
              ),
            ),
          ],
           const SizedBox(height: 12),

          // About: version, changelog, manual update check, ko-fi.
          _sectionLabel(tr('about_title'), p),
          _card(
            p,
            child: InkWell(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AboutScreen(model: model))),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: p.textSoft),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TN ' + appBuildVersion.replaceFirst('v', ''),
                            style: TextStyle(fontSize: 14.5, color: p.text)),
                        Text(tr('about_tagline'),
                            style: TextStyle(fontSize: 11, color: p.textFaint)),
                      ],
                    ),
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
        padding: const EdgeInsets.only(top: 20, bottom: 8, left: 2),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: p.textFaint)),
      );

  Widget _card(Palette p, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: p.bgChat,
          borderRadius: BorderRadius.circular(TNRadii.md),
          border: Border.all(color: p.divider.withValues(alpha: p.isDark ? 0.45 : 0.35)),
          boxShadow: p.cardShadow,
        ),
        child: child,
      );

  Widget _cacheRow(String label, int bytes, Palette p, {bool isTrash = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: p.textSoft)),
          Text(humanBytes(bytes),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isTrash && bytes > 50 * 1024 * 1024 ? p.danger : p.text)),
        ],
      );

  Widget _smartFolderToggle({
    required Palette p,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: value ? p.accent.withValues(alpha: 0.08) : p.bgList,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: value ? p.accent.withValues(alpha: 0.4) : p.divider.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: value ? p.accent : p.textFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: p.textFaint)),
                ],
              ),
            ),
            Switch(value: value, activeColor: p.accent, onChanged: onChanged),
          ],
        ),
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