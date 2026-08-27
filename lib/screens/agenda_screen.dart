import 'dart:async';

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/models.dart';
import '../src/sound.dart';
import '../src/state.dart';
import '../src/theme.dart';

/// Agenda: every undone todo with a deadline, grouped by day — today first,
/// then the coming days. Items toggle right here, mirroring the chat.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, required this.model});

  final AppModel model;

  /// Pure grouping used by tests: (dayStartMillis -> entries), overdue folded
  /// into today. Only undone todo entries of live chats are included.
  static Map<int, List<Entry>> groupByDay(AppState state, DateTime now) {
    final trashed = state.chats.where((c) => c.isTrashed).map((c) => c.id).toSet();
    final today = DateTime(now.year, now.month, now.day);
    final out = <int, List<Entry>>{};
    for (final e in state.entries) {
      if (e.type != 'todo' || e.dueAt == null) continue;
      if (trashed.contains(e.chatId)) continue;
      final items = e.items;
      if (items != null && items.isNotEmpty && items.every((i) => i.done)) continue;
      final due = DateTime.fromMillisecondsSinceEpoch(e.dueAt!);
      var day = DateTime(due.year, due.month, due.day);
      if (day.isBefore(today)) day = today; // overdue joins "today"
      out.putIfAbsent(day.millisecondsSinceEpoch, () => []).add(e);
    }
    for (final list in out.values) {
      list.sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    }
    return Map.fromEntries(
        out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  String _filter = 'all'; // all | overdue | today | week | high

  String _dayLabel(int dayMs, String Function(String, [List<String>?]) tr) {
    final dt = DateTime.fromMillisecondsSinceEpoch(dayMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return tr('today');
    if (day == today.add(const Duration(days: 1))) {
      return tr('tomorrow');
    }
    return '${dt.day} ${tr('month_${dt.month}')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.model.p;
    final tr = widget.model.tr;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final allGroups = AgendaScreen.groupByDay(widget.model.state, DateTime.now());
    // Apply filter
    final filtered = <int, List<Entry>>{};
    for (final entry in allGroups.entries) {
      final list = entry.value.where((e) {
        final overdue = e.dueAt! < nowMs;
        final isToday = entry.key == DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).millisecondsSinceEpoch;
        final isWeek = entry.key <= DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
        final isHigh = (e.items ?? const <TodoItem>[]).any((i) => i.priority == 2 && !i.done);
        switch (_filter) {
          case 'overdue':
            return overdue;
          case 'today':
            return isToday;
          case 'week':
            return isWeek;
          case 'high':
            return isHigh;
          default:
            return true;
        }
      }).toList();
      if (list.isNotEmpty) filtered[entry.key] = list;
    }

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(tr('agenda_title'),
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              for (final f in [
                ('all', tr('widget_all')),
                ('overdue', tr('overdue')),
                ('today', tr('today')),
                ('week', tr('filter_week')),
                ('high', tr('priority_2')),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: _filter == f.$1,
                    onSelected: (_) => setState(() => _filter = f.$1),
                    selectedColor: p.accent,
                    backgroundColor: p.bgChat,
                    labelStyle: TextStyle(fontSize: 13, color: _filter == f.$1 ? Colors.white : p.textSoft, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TNRadii.pill), side: BorderSide(color: _filter == f.$1 ? p.accent : p.divider)),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: tnEmptyState(p: p, icon: Icons.event_available_outlined, title: tr('nothing_found'), subtitle: 'Try another filter'),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      for (final entry in filtered.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                          child: Text(_dayLabel(entry.key, tr),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .3,
                                  color: p.textFaint)),
                        ),
                        for (final e in entry.value)
                          _taskCard(context, p, tr, e),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(BuildContext context, Palette p,
      String Function(String, [List<String>?]) tr, Entry e) {
    final overdue =
        e.dueAt! < DateTime.now().millisecondsSinceEpoch;
    final items = e.items ?? const <TodoItem>[];
    final chat = widget.model.state.chatById(e.chatId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.bgChat,
        borderRadius: BorderRadius.circular(TNRadii.md),
        border: Border.all(
            color: overdue
                ? p.danger.withValues(alpha: .45)
                : p.divider.withValues(alpha: p.isDark ? 0.45 : 0.35)),
        boxShadow: p.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(overdue ? Icons.warning_amber_rounded : Icons.schedule,
                size: 13,
                color: overdue ? p.danger : p.accent),
            const SizedBox(width: 5),
            Text(fmtTime(e.dueAt!),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: overdue ? p.danger : p.accent)),
            if (chat != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(chat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.textFaint)),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          for (final it in items)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _toggle(e, it),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: it.done ? p.accent : Colors.transparent,
                      border: Border.all(
                          color: it.done
                              ? p.accent
                              : p.textFaint.withValues(alpha: .55),
                          width: 2),
                    ),
                    child:
                        it.done ? Icon(Icons.check, size: 11, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(it.text,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: it.done ? p.textFaint : p.text,
                            decoration: it.done
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: p.textFaint)),
                  ),
                  if (it.priority > 0)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(color: p.priority(it.priority), shape: BoxShape.circle),
                    ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggle(Entry e, TodoItem it) async {
    toggleTodoCascade(e.items ??= <TodoItem>[], it.id);
    e.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (it.done) unawaited(Sounds.taskDone());
    await widget.model.save();
    widget.model.refresh();
    if (mounted) setState(() {});
  }
}
