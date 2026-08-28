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
  String _period = 'upcoming'; // 'today' | 'upcoming'
  String _sort = 'priority'; // 'priority' | 'time'

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
    final sort = prefs.getString('tn-widget-sort') ?? 'priority';
    if (!mounted) return;
    setState(() {
      _alpha = alpha.clamp(0.2, 1.0);
      _font = font.clamp(0.8, 1.6);
      _period = ['today', 'upcoming'].contains(period) ? period : 'upcoming';
      _sort = ['priority', 'time'].contains(sort) ? sort : 'priority';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tn-widget-alpha', _alpha);
    await prefs.setDouble('tn-widget-font', _font);
    await prefs.setString('tn-daywidget-period', _period);
    await prefs.setString('tn-widget-sort', _sort);
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
                    for (final (val, key) in [('today', 'dw_period_today'), ('upcoming', 'dw_period_upcoming')]) ...[
                      Expanded(
                        child: _periodButton(p, val, tr(key)),
                      ),
                      if (key != 'dw_period_upcoming') const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(tr('dw_sort_hint'),
                    style: TextStyle(fontSize: 11.5, color: p.textFaint)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (val, key) in [('priority', 'dw_sort_priority'), ('time', 'dw_sort_time')]) ...[
                      Expanded(
                        child: _sortButton(p, val, tr(key)),
                      ),
                      if (key != 'dw_sort_time') const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(tr('dw_sort_sub'),
                    style: TextStyle(fontSize: 10.5, color: p.textFaint)),
                const SizedBox(height: 6),
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

  Widget _sortButton(Palette p, String value, String title) {
    final selected = _sort == value;
    return InkWell(
      onTap: () async { setState(() => _sort = value); await _save(); },
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
    final model = widget.model;
    // Mirrors the native widget layout (tn_day_widget.xml): dark rounded
    // card, header pill with count badge + gear, task rows as inner cards.
    Widget row(String time, String chat, String text,
        {bool overdue = false, int priority = 0}) {
      final color = overdue ? const Color(0xFFFF6B6B) : const Color(0xFFEAECEF);
      final priColor = switch (priority) {
        1 => const Color(0xFFF0B429),
        2 => const Color(0xFFF07575),
        _ => const Color(0xFF6BCE6F),
      };
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(9, 7, 10, 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: priority == 0
              ? null
              : Border.all(color: priColor.withValues(alpha: .45), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (priority > 0) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: priColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ],
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8A9BA8), width: 1.6),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12 * _font, height: 1.2, color: color)),
                  const SizedBox(height: 2),
                  Text('$time · $chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10 * _font,
                          color: overdue ? const Color(0xFFFF6B6B) : const Color(0xFF8A9BA8))),
                ],
              ),
            ),
            if (overdue)
              Container(
                width: 6,
                height: 6,
                decoration:
                    const BoxDecoration(color: Color(0xFFFF6B6B), shape: BoxShape.circle),
              ),
          ],
        ),
      );
    }

    Widget badge(String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF2AABEE).withValues(alpha: .2),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10 * _font,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFEAECEF))),
        );

    return Container(
      width: 250,
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.fromARGB((_alpha * 255).round(), 0x17, 0x21, 0x2B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header pill
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 15 * _font, color: p.accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(model.tr('kind_tasks'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13 * _font,
                          fontWeight: FontWeight.w700,
                          color: p.accent)),
                ),
                badge('2'),
                const SizedBox(width: 8),
                Icon(Icons.settings, size: 14 * _font, color: const Color(0xFF8A9BA8)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(model.tr('today'),
              style: TextStyle(fontSize: 10 * _font, fontWeight: FontWeight.w700, color: const Color(0xFF8A9BA8))),
          row('09:30', model.tr('dw_period_today'), 'Купить кофе', overdue: true, priority: 2),
          row('12:00', model.tr('today'), 'Позвонить маме', priority: 1),
          row('18:45', model.tr('tags_title'), '#идеи записать мысль'),
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
