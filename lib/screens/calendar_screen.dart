import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/models.dart';
import '../src/theme.dart';
import 'chat_screen.dart';

/// Month view across every chat: dots mark days with entries/tasks.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _day(DateTime.now());

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  int _dateOf(Entry e) {
    final ms = e.dueAt ?? e.ts;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
  }

  List<Entry> _entries() {
    final chats = {
      for (final c in widget.model.state.chats)
        if (!c.isTrashed) c.id: c,
    };
    return widget.model.state.entries
        .where((e) => chats.containsKey(e.chatId))
        .toList();
  }

  List<Entry> _onDay(List<Entry> all, DateTime day) {
    final key = day.millisecondsSinceEpoch;
    final list = all.where((e) => _dateOf(e) == key).toList()
      ..sort((a, b) => (a.dueAt ?? a.ts).compareTo(b.dueAt ?? b.ts));
    return list;
  }

  IconData _icon(Entry e) => switch (e.type) {
        'image' => Icons.image_outlined,
        'audio' => Icons.mic_none_rounded,
        'video' => Icons.videocam_outlined,
        'doc' => Icons.insert_drive_file_outlined,
        'todo' => Icons.checklist_rounded,
        _ => Icons.article_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final p = widget.model.p;
    final tr = widget.model.tr;
    final all = _entries();
    final selectedEntries = _onDay(all, _selected);
    final counts = <int, int>{};
    for (final e in all) {
      counts[_dateOf(e)] = (counts[_dateOf(e)] ?? 0) + 1;
    }

    final today = _day(DateTime.now());
    final first = DateTime(_month.year, _month.month);
    final leading = first.weekday - 1;
    final weekDays = tr('weekdays_short').split(' ');

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          tr('calendar_title'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: p.textSoft),
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${tr('month_${_month.month}')} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: p.textSoft),
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 0; i < 7 && i < weekDays.length; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        weekDays[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: p.textFaint,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              childAspectRatio: 1.05,
              children: [
                for (var i = 0; i < 42; i++)
                  _cell(
                    p,
                    DateTime(first.year, first.month, first.day - leading + i),
                    counts,
                    today,
                  ),
              ],
            ),
            Divider(height: 1, color: p.divider),
            Expanded(
              child: selectedEntries.isEmpty
                  ? Center(
                      child: Text(
                        tr('calendar_empty'),
                        style: TextStyle(fontSize: 13.5, color: p.textFaint),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: selectedEntries.length,
                      itemBuilder: (ctx, i) {
                        final e = selectedEntries[i];
                        final chat = widget.model.state.chatById(e.chatId);
                        if (chat == null) return const SizedBox.shrink();
                        return ListTile(
                          leading: Icon(_icon(e), size: 20, color: p.accent),
                          title: Text(
                            entryPreview(e, tr),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: p.text),
                          ),
                          subtitle: Text(
                            '${chat.name} • ${fmtTime((e.dueAt ?? e.ts))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: p.textFaint),
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  model: widget.model,
                                  chatId: chat.id,
                                  scrollToEntryId: e.id,
                                  highlightEntryId: e.id,
                                ),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    Palette p,
    DateTime day,
    Map<int, int> counts,
    DateTime today,
  ) {
    final inMonth = day.month == _month.month;
    final count = counts[day.millisecondsSinceEpoch] ?? 0;
    final selected = day == _selected;
    final isToday = day == today;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selected = day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected
              ? p.accent.withValues(alpha: .16)
              : isToday
              ? p.accent.withValues(alpha: .08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: p.accent, width: 1.2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w500,
                color: !inMonth
                    ? p.textFaint.withValues(alpha: .35)
                    : selected
                    ? p.accent
                    : p.text,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: count > 0 && inMonth ? p.accent : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
