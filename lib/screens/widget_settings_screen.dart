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
  double _alpha = 1.0;
  double _font = 1.0;
  String _period = 'all'; // 'all' | 'today' | 'week'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var alpha = 1.0;
    try {
      alpha = prefs.getDouble('tn-widget-alpha') ?? 1.0;
    } catch (_) {
      try {
        final s = prefs.getString('tn-widget-alpha');
        if (s != null) alpha = double.tryParse(s) ?? 1.0;
      } catch (_) {}
    }
    var font = 1.0;
    try {
      font = prefs.getDouble('tn-widget-font') ?? 1.0;
    } catch (_) {
      try {
        final s = prefs.getString('tn-widget-font');
        if (s != null) font = double.tryParse(s) ?? 1.0;
      } catch (_) {}
    }
    final period = prefs.getString('tn-daywidget-period') ?? 'all';
    if (!mounted) return;
    setState(() {
      _alpha = alpha.clamp(0.2, 1.0);
      _font = font.clamp(0.8, 1.6);
      _period = ['all', 'today', 'week'].contains(period) ? period : 'all';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tn-widget-alpha', _alpha);
    await prefs.setDouble('tn-widget-font', _font);
    await prefs.setString('tn-daywidget-period', _period);
    await WidgetBridge.refresh();
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
        title: Text(tr('widget_settings_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(icon: Icon(Icons.arrow_back, color: p.textSoft), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 4),
          Center(child: _preview(p)),
          _sectionLabel(tr('dw_settings_title'), p),
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                  child: Text(tr('dw_period_hint'),
                      style: TextStyle(fontSize: 11.5, color: p.textFaint)),
                ),
                Row(
                  children: [
                    for (final (val, key) in [('all', 'dw_period_all'), ('today', 'dw_period_today'), ('week', 'dw_period_week')]) ...[
                      Expanded(
                        child: _periodButton(p, val, tr(key)),
                      ),
                      if (key != 'dw_period_week') const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
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
          _sectionLabel(tr('widget_font'), p),
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: _font,
                  min: 0.8,
                  max: 1.6,
                  divisions: 8,
                  label: '${(_font * 100).round()}%',
                  activeColor: p.accent,
                  inactiveColor: p.divider,
                  onChanged: (v) => setState(() => _font = v),
                  onChangeEnd: (v) async { _font = v; await _save(); },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${(_font * 100).round()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.accent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _periodButton(Palette p, String value, String title) {
    final selected = _period == value;
    return InkWell(
      onTap: () async { setState(() => _period = value); await _save(); },
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
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? p.accent : p.textSoft)),
      ),
    );
  }

  Widget _preview(Palette p) {
    final sampleRows = ['09:30 • работа   купить кофе', '12:00 • сегодня  позвонить маме', '18:45 • идеи     записать мысль'];
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: const Color(0x2E000000), borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Задачи', style: TextStyle(fontSize: 13 * _font, fontWeight: FontWeight.w700, color: p.accent)),
                Icon(Icons.settings, size: 16 * _font, color: const Color(0xFF8A9BA8)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final row in sampleRows)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(row, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5 * _font, color: const Color(0xFFEAECEF))),
            ),
        ],
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
