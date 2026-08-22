import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/app_model.dart';
import '../src/theme.dart';
import '../src/widget_bridge.dart';

class WidgetSettingsScreen extends StatefulWidget {
  const WidgetSettingsScreen({super.key, required this.model});
  final AppModel model;
  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  String _chat = '';
  double _alpha = 1.0;
  String _dayMode = 'tasks'; // 'tasks' | 'notes'
  String _dayChat = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final chat = prefs.getString('tn-widget-chatId') ?? '';
    var alpha = 1.0;
    try {
      alpha = prefs.getDouble('tn-widget-alpha') ?? 1.0;
    } catch (_) {
      try {
        final s = prefs.getString('tn-widget-alpha');
        if (s != null) alpha = double.tryParse(s) ?? 1.0;
      } catch (_) {}
    }
    final dayMode = prefs.getString('tn-daywidget-mode') ?? 'tasks';
    final dayChat = prefs.getString('tn-daywidget-chatId') ?? '';
    if (!mounted) return;
    setState(() {
      _chat = chat;
      _alpha = alpha.clamp(0.2, 1.0);
      _dayMode = dayMode == 'notes' ? 'notes' : 'tasks';
      _dayChat = dayChat;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tn-widget-chatId', _chat);
    await prefs.setDouble('tn-widget-alpha', _alpha);
    await prefs.setString('tn-daywidget-mode', _dayMode);
    await prefs.setString('tn-daywidget-chatId', _dayChat);
    await WidgetBridge.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final p = model.p;
    final tr = model.tr;
    final validValues = ['', ...model.state.chats.map((c) => c.id)];
    if (!validValues.contains(_chat)) _chat = '';
    if (!model.state.chats.any((c) => c.id == _dayChat)) _dayChat = '';

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(tr('widget_settings_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(icon: Icon(Icons.arrow_back, color: p.textSoft), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 4),
          Center(child: _preview(p)),
          _sectionLabel(tr('widget_chat'), p),
          _card(
            p,
            child: Column(
              children: [
                _option(p, value: '', title: tr('widget_all')),
                for (final c in model.state.chats) ...[
                  Divider(height: 1, color: p.divider),
                  _option(p, value: c.id, title: c.name),
                ],
              ],
            ),
          ),
          _sectionLabel(tr('widget_transparency'), p),
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: _alpha,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  label: '${(_alpha * 100).round()}%',
                  activeColor: p.accent,
                  inactiveColor: p.divider,
                  onChanged: (v) => setState(() => _alpha = v),
                  onChangeEnd: (v) async { _alpha = v; await _save(); },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${(_alpha * 100).round()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.accent)),
                ),
                Text(tr('widget_transparency_hint'), style: TextStyle(fontSize: 11.5, color: p.textFaint)),
              ],
            ),
          ),
          _sectionLabel(tr('dw_settings_title'), p),
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                  child: Text(tr('ac_hint'),
                      style: TextStyle(fontSize: 11.5, color: p.textFaint)),
                ),
                Row(
                  children: [
                    for (final (val, key) in [('tasks', 'dw_mode_tasks'), ('notes', 'dw_mode_notes')]) ...[
                      Expanded(
                        child: _modeButton(p, val, tr(key)),
                      ),
                      if (key == 'dw_mode_tasks') const SizedBox(width: 8),
                    ],
                  ],
                ),
                Divider(height: 20, color: p.divider),
                Text(tr('widget_chat'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                const SizedBox(height: 4),
                _dayChatOption(p, '', tr('widget_all')),
                for (final c in model.state.chats) _dayChatOption(p, c.id, c.name),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _modeButton(Palette p, String value, String title) {
    final selected = _dayMode == value;
    return InkWell(
      onTap: () async { setState(() => _dayMode = value); await _save(); },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: .18) : p.bgList,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? p.accent : p.divider, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? p.accent : p.textSoft)),
      ),
    );
  }

  Widget _dayChatOption(Palette p, String value, String title) {
    final selected = _dayChat == value;
    return InkWell(
      onTap: () async { setState(() => _dayChat = value); await _save(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18, color: selected ? p.accent : p.textFaint),
            const SizedBox(width: 10),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: p.text))),
          ],
        ),
      ),
    );
  }

  Widget _preview(Palette p) {
    final sampleRows = ['09:30  Идеи: купить кофе', '12:00  Задачи: ☐ Позвонить', '18:45  Дневник: хороший день'];
    return Container(
      width: 250,
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.fromARGB((_alpha * 255).round(), 0x17, 0x21, 0x2B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.accent)),
              const Icon(Icons.settings, size: 16, color: Color(0xFF8A9BA8)),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in sampleRows)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(row, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFFEAECEF))),
            ),
        ],
      ),
    );
  }

  Widget _option(Palette p, {required String value, required String title}) {
    final selected = _chat == value;
    return InkWell(
      onTap: () async { setState(() => _chat = value); await _save(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: selected ? p.accent : p.textFaint),
            const SizedBox(width: 10),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.text))),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, Palette p) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textFaint)),
      );

  Widget _card(Palette p, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(12)),
        child: child,
      );
}
