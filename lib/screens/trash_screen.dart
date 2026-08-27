import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/app_model.dart';
import '../src/media.dart';
import '../src/models.dart';
import '../src/theme.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  int _retentionDays = 7;

  @override
  void initState() {
    super.initState();
    _loadRetention();
  }

  Future<void> _loadRetention() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('tn-trash-retention-days') ?? 7;
      if (mounted) setState(() => _retentionDays = v);
    } catch (_) {}
  }

  Future<void> _saveRetention(int days) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tn-trash-retention-days', days);
      if (mounted) setState(() => _retentionDays = days);
    } catch (_) {}
  }

  Future<void> _restore(Chat chat) async {
    chat.deletedAt = null;
    await widget.model.save();
    if (mounted) setState(() {});
  }

  Future<void> _deleteForever(Chat chat) async {
    final model = widget.model;
    for (final e in model.state.entriesFor(chat.id)) {
      try {
        final store = MediaStore();
        await store.remove(e.media);
      } catch (_) {}
    }
    for (final r in model.state.reminders.toList()) {
      if (r.chatId == chat.id) model.state.reminders.remove(r);
    }
    model.state.entries.removeWhere((e) => e.chatId == chat.id);
    model.state.chats.removeWhere((c) => c.id == chat.id);
    await model.save();
    if (mounted) setState(() {});
  }

  Future<void> _emptyTrash() async {
    final model = widget.model;
    final trashed = model.state.chats.where((c) => c.isTrashed).toList();
    for (final chat in trashed) {
      for (final e in model.state.entriesFor(chat.id)) {
        try {
          final store = MediaStore();
          await store.remove(e.media);
        } catch (_) {}
      }
      for (final r in model.state.reminders.toList()) {
        if (r.chatId == chat.id) model.state.reminders.remove(r);
      }
      model.state.entries.removeWhere((e) => e.chatId == chat.id);
    }
    model.state.chats.removeWhere((c) => c.isTrashed);
    await model.save();
    if (mounted) setState(() {});
  }

  String _retentionLabel(int days) {
    switch (days) {
      case 1:
        return '1 ${widget.model.tr('day')}';
      case 7:
        return '7 ${widget.model.tr('days')}';
      case 30:
        return '30 ${widget.model.tr('days')}';
      case 0:
        return widget.model.tr('forever');
      default:
        return '$days ${widget.model.tr('days')}';
    }
  }

  static const _retentionValues = [1, 7, 30, 0];

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final p = model.p;
    final tr = model.tr;
    final trashed = model.state.chats.where((c) => c.isTrashed).toList()
      ..sort((a, b) => (b.deletedAt ?? 0).compareTo(a.deletedAt ?? 0));

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(tr('trash'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (trashed.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              tooltip: tr('empty_trash'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: p.modalBg,
                    title: Text(tr('empty_trash'),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                    content: Text(tr('empty_trash_confirm'),
                        style: TextStyle(fontSize: 14, color: p.textSoft)),
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
                if (ok == true) _emptyTrash();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _sectionLabel(tr('retention'), p),
          _card(p, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('retention_hint'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: p.textFaint)),
              Slider(
                value: _retentionValues.indexOf(_retentionDays).clamp(0, 3).toDouble(),
                min: 0,
                max: 3,
                divisions: 3,
                label: _retentionLabel(_retentionDays),
                activeColor: p.accent,
                inactiveColor: p.divider,
                thumbColor: p.accent,
                onChanged: (v) =>
                    setState(() => _retentionDays = _retentionValues[v.round()]),
                onChangeEnd: (v) => _saveRetention(_retentionValues[v.round()]),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(_retentionLabel(_retentionDays),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.textSoft)),
              ),
            ],
          )),
          const SizedBox(height: 8),
          _sectionLabel('${tr('trash')} (${trashed.length})', p),
          if (trashed.isEmpty)
            _card(p, child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(tr('trash_empty'),
                    style: TextStyle(fontSize: 14, color: p.textFaint)),
              ),
            ))
          else
            for (final chat in trashed)
              _trashChatRow(chat, p, tr),
        ],
      ),
    );
  }

  Widget _trashChatRow(Chat chat, Palette p, String Function(String, [List<String>?]) tr) {
    final deletedAgo = chat.deletedAt != null
        ? _formatDeletedAgo(DateTime.now().millisecondsSinceEpoch - chat.deletedAt!)
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.bgChat,
        borderRadius: BorderRadius.circular(TNRadii.md),
        border: Border.all(color: p.divider.withValues(alpha: p.isDark ? 0.45 : 0.35)),
        boxShadow: p.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(chat.icon ?? '📝', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.name,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                    if (deletedAgo.isNotEmpty)
                      Text(deletedAgo,
                          style: TextStyle(fontSize: 12, color: p.textFaint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _restore(chat),
                icon: Icon(Icons.restore, size: 18, color: p.accent),
                label: Text(tr('restore'), style: TextStyle(color: p.accent)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _deleteForever(chat),
                icon: Icon(Icons.delete_forever, size: 18, color: p.danger),
                label: Text(tr('delete_forever'), style: TextStyle(color: p.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDeletedAgo(int millis) {
    final tr = widget.model.tr;
    final days = millis ~/ 86400000;
    if (days > 0) return tr('deleted_ago_days', ['$days']);
    final hours = millis ~/ 3600000;
    if (hours > 0) return tr('deleted_ago_hours', ['$hours']);
    return tr('just_now');
  }

  Widget _sectionLabel(String label, Palette p) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8, left: 2),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.textFaint)),
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
}
