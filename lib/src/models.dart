import 'dart:math';

const storageKey = 'tn-notes-data-v1';
const mediaDirName = 'tn_media';

const appColors = [
  '#2AABEE', '#E0663E', '#7C5CD6', '#3EA66E',
  '#D6538B', '#C99A2E', '#5C7CFA', '#20B2AA',
];

const appIcons = <String?>[
  null, '💡', '📌', '💼', '🎯', '📚', '🎨', '🎧', '🍳', '✈️', '🌱', '⚡', '🧠', '❤️', '🏋️', '🎵',
  '🔥', '💎', '🌟', '⭐', '🌈', '🍀', '🎁', '🏆', '📅', '📊', '🗂️', '💬', '🔔', '🔖', '🧩',
  '🎭', '🎬', '🎤', '🎹', '🏝️', '🏠', '🚀', '🛠️', '📈', '📉', '🔬', '🧪',
];

class Folder {
  Folder({required this.id, required this.name, this.color});

  final String id;
  String name;
  String? color; // hex like '#2AABEE', null = default

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        color: j['color'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (color != null) 'color': color,
      };
}

const chatKinds = [
  ('note', '📝'),
  ('rss', '📡'),
  ('tasks', '✅'),
  ('kanban', '🗂️'),
];

/// One kanban column (tab inside a kanban chat).
/// Default columns use stable ids 'idea' / 'work' / 'done' so old entries
/// and cross-device merges keep working. Custom columns use uid('b').
class BoardColumn {
  BoardColumn({required this.id, required this.name});

  final String id;
  String name;

  factory BoardColumn.fromJson(Map<String, dynamic> j) => BoardColumn(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Builds the 3 default columns with localized names. Caller passes
/// already-translated strings so models.dart stays i18n-free.
List<BoardColumn> defaultBoardColumns(String idea, String work, String done) =>
    [
      BoardColumn(id: 'idea', name: idea),
      BoardColumn(id: 'work', name: work),
      BoardColumn(id: 'done', name: done),
    ];

/// Rule that pulls entries from other chats into this one ("flexible chats"):
/// e.g. a "Today" chat collecting every task due today.
class AutoCollect {
  AutoCollect({
    this.enabled = false,
    this.fromAllChats = true,
    this.sourceFolderId,
    this.typeFilter = 'all', // 'all' | 'todo' | 'note'
    this.dueFilter = 'any', // 'any' | 'today'
  });

  bool enabled;
  bool fromAllChats;
  String? sourceFolderId;
  String typeFilter;
  String dueFilter;

  factory AutoCollect.fromJson(Map<String, dynamic> j) => AutoCollect(
        enabled: j['enabled'] as bool? ?? false,
        fromAllChats: j['fromAllChats'] as bool? ?? true,
        sourceFolderId: j['sourceFolderId'] as String?,
        typeFilter: j['typeFilter'] as String? ?? 'all',
        dueFilter: j['dueFilter'] as String? ?? 'any',
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'fromAllChats': fromAllChats,
        'typeFilter': typeFilter,
        'dueFilter': dueFilter,
        if (sourceFolderId != null) 'sourceFolderId': sourceFolderId,
      };
}

class Chat {
  Chat({
    required this.id,
    required this.name,
    required this.color,
    this.icon,
    this.pinned = false,
    this.archived = false,
    this.folderId,
    this.kind = 'note',
    this.tasksHideDone = false,
    this.rssUrl,
    this.notificationsEnabled = true,
    this.notificationSound,
    this.autoCollect,
    this.deletedAt,
    this.p2pRoomId,
    this.p2pRole,
    this.board,
    int? createdAt,
    this.order = 0,
  }) : createdAt = createdAt ?? createdAtFromId(id);

  final String id;
  String name;
  String color;
  String? icon;
  bool pinned = false;
  bool archived = false;
  String? folderId;
  String kind = 'note';
  bool tasksHideDone = false;
  String? rssUrl;
  bool notificationsEnabled = true;
  String? notificationSound;
  AutoCollect? autoCollect;
  int? deletedAt; // millis when moved to trash; null = active

  /// Creation instant (old backups fall back to the timestamp inside [id]).
  final int createdAt;

  /// Manual sort position; only used when the user picks manual sorting.
  int order;

  /// P2P shared chat (beta). roomId = hex of the invite's 8-byte id;
  /// role = host | guest. The invite SECRET never lives here — only in prefs.
  String? p2pRoomId;
  String? p2pRole;

  /// Kanban columns. Null/empty = 3 defaults (idea/work/done) resolved
  /// at display time via [effectiveBoard] — keeps old backups working.
  List<BoardColumn>? board;

  bool get isTrashed => deletedAt != null;
  bool get isKanban => kind == 'kanban';

  /// Columns to show. Pass the translator: tr('board_idea') etc.
  List<BoardColumn> effectiveBoard(String Function(String, [List<String>?]) tr) {
    if (board != null && board!.isNotEmpty) return board!;
    return defaultBoardColumns(tr('board_idea'), tr('board_work'), tr('board_done'));
  }

  void ensureBoard(String Function(String, [List<String>?]) tr) {
    if (board == null || board!.isEmpty) {
      board = defaultBoardColumns(tr('board_idea'), tr('board_work'), tr('board_done'));
    }
  }

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        color: j['color'] as String? ?? appColors[0],
        icon: j['icon'] as String?,
        pinned: j['pinned'] as bool? ?? false,
        archived: j['archived'] as bool? ?? false,
        folderId: j['folderId'] as String?,
        kind: j['kind'] as String? ?? 'note',
        tasksHideDone: j['tasksHideDone'] as bool? ?? false,
        rssUrl: j['rssUrl'] as String?,
        notificationsEnabled: j['notificationsEnabled'] as bool? ?? true,
        notificationSound: j['notificationSound'] as String?,
        deletedAt: (j['deletedAt'] as num?)?.toInt(),
        p2pRoomId: j['p2pRoomId'] as String?,
        p2pRole: j['p2pRole'] as String?,
        autoCollect: j['autoCollect'] == null
            ? null
            : AutoCollect.fromJson(j['autoCollect'] as Map<String, dynamic>),
        board: (j['board'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(BoardColumn.fromJson)
            .toList(),
        createdAt: (j['createdAt'] as num?)?.toInt(),
        order: (j['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'icon': icon,
        'pinned': pinned,
        'archived': archived,
        'kind': kind,
        'tasksHideDone': tasksHideDone,
        'notificationsEnabled': notificationsEnabled,
        if (notificationSound != null) 'notificationSound': notificationSound,
        if (rssUrl != null) 'rssUrl': rssUrl,
        if (folderId != null) 'folderId': folderId,
        if (deletedAt != null) 'deletedAt': deletedAt,
        if (p2pRoomId != null) 'p2pRoomId': p2pRoomId,
        if (p2pRole != null) 'p2pRole': p2pRole,
        if (autoCollect != null) 'autoCollect': autoCollect!.toJson(),
        if (board != null && board!.isNotEmpty)
          'board': board!.map((b) => b.toJson()).toList(),
        'createdAt': createdAt,
        if (order != 0) 'order': order,
      };
}

/// `uid` embeds microseconds since epoch: `c-<micros>-<random>`.
int createdAtFromId(String id) {
  final parts = id.split('-');
  if (parts.length < 3) return 0;
  final micros = int.tryParse(parts[1]);
  return micros == null ? 0 : micros ~/ 1000;
}

/// Kanban helpers (pure, testable). [tr] is the app translator.
String resolvedBoardId(
    Entry e, Chat c, String Function(String, [List<String>?]) tr) {
  final boards = c.effectiveBoard(tr);
  if (e.boardId != null && boards.any((b) => b.id == e.boardId)) {
    return e.boardId!;
  }
  return boards.first.id;
}

String boardNameFor(
    Entry e, Chat c, String Function(String, [List<String>?]) tr) {
  final id = resolvedBoardId(e, c, tr);
  return c.effectiveBoard(tr).firstWhere((b) => b.id == id).name;
}

/// Next column id when swiping right, or null when already last.
/// Backwards moves are menu-only by design (beta decision).
String? nextBoardId(
    Entry e, Chat c, String Function(String, [List<String>?]) tr) {
  final boards = c.effectiveBoard(tr);
  final cur = resolvedBoardId(e, c, tr);
  final i = boards.indexWhere((b) => b.id == cur);
  if (i < 0 || i + 1 >= boards.length) return null;
  return boards[i + 1].id;
}

/// Moves [e] to [targetId]. When the target is the last column ("Done"),
/// every todo item is auto-checked (deadline stops ringing). When leaving
/// the last column backwards via menu, items go back to undone.
/// Returns the previous column id (for Undo snackbars).
String moveEntryToBoard(
  Entry e,
  Chat c,
  String targetId,
  String Function(String, [List<String>?]) tr,
) {
  final boards = c.effectiveBoard(tr);
  final prev = resolvedBoardId(e, c, tr);
  e.boardId = targetId;
  e.updatedAt = DateTime.now().millisecondsSinceEpoch;
  final isLast = boards.isNotEmpty && boards.last.id == targetId;
  final wasLast = boards.isNotEmpty && boards.last.id == prev;
  if (e.type == 'todo' && e.items != null) {
    if (isLast) {
      for (final it in e.items!) {
        it.done = true;
      }
    } else if (wasLast) {
      for (final it in e.items!) {
        it.done = false;
      }
    }
  }
  return prev;
}

class TodoItem {
  TodoItem({required this.id, required this.text, this.done = false, this.parentId, this.priority = 0});

  final String id;
  String text;
  bool done;

  /// Non-null when this item is a subtask of another item in the same entry.
  String? parentId;

  /// Task importance profile: 0 = normal, 1 = medium, 2 = high.
  int priority;

  factory TodoItem.fromJson(Map<String, dynamic> j) => TodoItem(
        id: j['id'] as String? ?? '',
        text: j['text'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        parentId: j['pid'] as String?,
        priority: (j['priority'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        if (parentId != null) 'pid': parentId,
        if (priority != 0) 'priority': priority,
      };
}

/// Toggles [id] and cascades the new value over its whole subtree (checking
/// a parent checks its subtasks, unchecking unchecks them). Pure function —
/// mutates [items] in place, returns true when anything changed.
/// Блок: родителя нельзя завершить пока есть незавершённые подзадачи.
bool toggleTodoCascade(List<TodoItem> items, String id) {
  final target = items.where((i) => i.id == id).firstOrNull;
  if (target == null) return false;
  final value = !target.done;
  if (value) {
    final hasUndoneChildren = items.any((c) => c.parentId == id && !c.done);
    if (hasUndoneChildren) return false;
  }
  void apply(TodoItem t) {
    t.done = value;
    for (final c in items.where((i) => i.parentId == t.id)) {
      apply(c);
    }
  }

  apply(target);
  return true;
}

/// Removes an item; its subtasks (if any) are re-parented to root level so
/// no text is ever lost. Returns true when the item existed.
bool removeTodoItem(List<TodoItem> items, String id) {
  final target = items.where((i) => i.id == id).firstOrNull;
  if (target == null) return false;
  final wasParent = target.parentId;
  for (final child in items.where((i) => i.parentId == id).toList()) {
    child.parentId = wasParent; // keep sibling level, or lift to root
  }
  items.removeWhere((i) => i.id == id);
  return true;
}

extension _FirstOf<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Forwarded copies get fresh todo ids: ids are looked up per entry today,
/// but duplicates across entries break any future global lookup and backups.
List<TodoItem>? _remapItemIds(List<TodoItem>? src) {
  if (src == null) return null;
  final ids = {for (final item in src) item.id: uid('t')};
  return src
      .map((item) => TodoItem(
            id: ids[item.id]!,
            text: item.text,
            done: item.done,
            parentId:
                item.parentId == null ? null : ids[item.parentId],
            priority: item.priority,
          ))
      .toList();
}

class Entry {
  Entry({
    required this.id,
    required this.chatId,
    required this.type,
    required this.ts,
    this.text = '',
    this.tags = const [],
    this.media,
    this.mediaName,
    this.mediaSize,
    this.duration,
    this.items,
    this.waveform,
    this.recurrence,
    this.recurrenceDays,
    this.monthDay,
    this.dueAt,
    this.editedAt,
    int? updatedAt,
    this.pinned = false,
    this.boardId,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String chatId;
  String type;
  final int ts;
  String text;
  List<String> tags;
  String? media;
  String? mediaName;
  String? mediaSize;
  int? duration;
  List<TodoItem>? items;
  // Delayed send was removed in v7.6: legacy `scheduledAt` values from old
  // backups are intentionally ignored on load and never written back.
  List<int>? waveform; // 0..100 amplitude bars for voice messages
  /// Recurrence rule for todo entries:
  /// null | 'daily' | 'weekly' (see [recurrenceDays]) | 'monthly' (see [monthDay]).
  String? recurrence;
  List<int>? recurrenceDays; // 1=Mon..7=Sun for weekly
  int? monthDay; // 1..31 for monthly, clamped to month length
  int? dueAt; // for tasks-chat todos: deadline millis
  int? editedAt; // millis when last edited
  int updatedAt; // millis of last local change (for sync merge)
  bool pinned; // pinned entries float to the top of the chat
  String? boardId; // kanban column id; null = first column

  bool get isEdited => editedAt != null;

  /// True when this is a todo whose every item is checked. Done tasks must
  /// never fire notifications — all alarm paths check this.
  bool get isDone =>
      type == 'todo' &&
      (items?.isNotEmpty ?? false) &&
      items!.every((i) => i.done);

  /// Deep copy of every content field into a fresh entry in [targetChatId].
  /// Used by forward — the old hand-rolled copies kept dropping recurrence
  /// fields (`monthDay`, sometimes `recurrenceDays`), breaking forwarded
  /// recurring tasks.
  Entry copyForForward(String targetChatId, {int? ts}) => Entry(
        id: uid('e'),
        chatId: targetChatId,
        type: type,
        ts: ts ?? DateTime.now().millisecondsSinceEpoch,
        text: text,
        tags: List.of(tags),
        media: media,
        mediaName: mediaName,
        mediaSize: mediaSize,
        duration: duration,
        waveform: waveform == null ? null : List.of(waveform!),
        items: _remapItemIds(items),
        dueAt: dueAt,
        recurrence: recurrence,
        recurrenceDays:
            recurrenceDays == null ? null : List.of(recurrenceDays!),
        monthDay: monthDay,
        boardId: boardId,
      );

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'] as String,
        chatId: j['chatId'] as String,
        type: j['type'] as String? ?? 'text',
        ts: (j['ts'] as num).toInt(),
        text: j['text'] as String? ?? '',
        tags: (j['tags'] as List?)?.map((e) => e as String).toList() ?? const [],
        media: j['media'] as String?,
        mediaName: j['mediaName'] as String?,
        mediaSize: j['mediaSize'] as String?,
        duration: (j['duration'] as num?)?.toInt(),
        waveform: (j['waveform'] as List?)?.map((e) => (e as num).toInt()).toList(),
        recurrence: j['recurrence'] as String?,
        recurrenceDays:
            (j['recurrenceDays'] as List?)?.map((e) => (e as num).toInt()).toList(),
        monthDay: (j['monthDay'] as num?)?.toInt(),
        dueAt: (j['dueAt'] as num?)?.toInt(),
        editedAt: (j['editedAt'] as num?)?.toInt(),
        updatedAt: (j['updatedAt'] as num?)?.toInt(),
        pinned: j['pinned'] as bool? ?? false,
        boardId: j['boardId'] as String?,
        items: (j['items'] as List?)
            ?.map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'type': type,
        'ts': ts,
        'text': text,
        'tags': tags,
        'media': media,
        'mediaName': mediaName,
        'mediaSize': mediaSize,
        'duration': duration,
        'items': items?.map((i) => i.toJson()).toList(),
        if (waveform != null) 'waveform': waveform,
        if (recurrence != null) 'recurrence': recurrence,
        if (recurrenceDays != null) 'recurrenceDays': recurrenceDays,
        if (monthDay != null) 'monthDay': monthDay,
        if (dueAt != null) 'dueAt': dueAt,
        if (editedAt != null) 'editedAt': editedAt,
        'updatedAt': updatedAt,
        if (pinned) 'pinned': pinned,
        if (boardId != null) 'boardId': boardId,
      };
}

class Reminder {
  Reminder({required this.id, required this.chatId, required this.when});

  final String id;
  final String chatId;
  final int when; // epoch millis

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String,
        chatId: j['chatId'] as String? ?? '',
        when: (j['when'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'chatId': chatId, 'when': when};
}

List<String> extractTags(String text) {
  final tags = <String>[];
  final re = RegExp(r'#([\wа-яёА-ЯЁіїєґІЇЄҐ]+)');
  for (final m in re.allMatches(text)) {
    final t = m.group(1)!.toLowerCase();
    if (!tags.contains(t)) tags.add(t);
  }
  return tags;
}

/// Time-based id plus 3 random bytes from a secure RNG — two ids created in
/// the same microsecond can no longer collide (the old millisecond-hex suffix
/// had very low entropy).
final Random _uidRandom = Random.secure();
String uid(String prefix) {
  final rnd = List.generate(3, (_) => _uidRandom.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$rnd';
}

/// Stable 31-bit FNV-1a hash. Unlike String.hashCode (randomized per process
/// in Dart), this is identical across app restarts — required for native
/// notification/alarm ids that must survive relaunches.
int stableHash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7FFFFFFF;
  }
  return h == 0 ? 1 : h;
}

/// Next occurrence of a recurrence rule strictly after [after].
///
/// [fromMs] is the anchor (usually the entry's current dueAt) — its clock
/// time is preserved across occurrences. Weekdays are ISO: 1=Mon..7=Sun.
/// Returns epoch millis.
int nextOccurrence({
  required String recurrence,
  List<int>? days,
  int? monthDay,
  required int fromMs,
  required DateTime after,
}) {
  final from = DateTime.fromMillisecondsSinceEpoch(fromMs);
  var cand = DateTime(from.year, from.month, from.day, from.hour, from.minute);

  // Calendar-day step: `add(Duration(days: 1))` shifts the wall clock by an
  // hour across DST boundaries, so a 09:00 daily task became 08:00/10:00.
  DateTime nextDay(DateTime d) =>
      DateTime(d.year, d.month, d.day + 1, from.hour, from.minute);

  switch (recurrence) {
    case 'daily':
      do {
        cand = nextDay(cand);
      } while (!cand.isAfter(after));
      break;
    case 'weekly':
      final set = (days == null || days.isEmpty)
          ? <int>{from.weekday}
          : Set<int>.of(days);
      do {
        cand = nextDay(cand);
      } while (!set.contains(cand.weekday) || !cand.isAfter(after));
      break;
    case 'monthly':
      final dom = (monthDay == null || monthDay < 1) ? from.day : monthDay;
      var y = from.year;
      var m = from.month;
      while (true) {
        m++;
        if (m > 12) {
          m = 1;
          y++;
        }
        final last = DateTime(y, m + 1, 0).day; // day count of month m
        final c = DateTime(y, m, dom > last ? last : dom, from.hour, from.minute);
        if (c.isAfter(after)) return c.millisecondsSinceEpoch;
      }
    default:
      // Unknown rule: behave like one-shot, push a day forward past [after].
      do {
        cand = nextDay(cand);
      } while (!cand.isAfter(after));
  }
  return cand.millisecondsSinceEpoch;
}

/// True when a recurring todo [e] has an occurrence on calendar [day]
/// (any time of day) — used to project future occurrences in the calendar.
/// Days before the current deadline's day never match (that history is
/// not stored). The current deadline's own day is not projected either:
/// the entry itself already sits there.
bool recursOnDay(Entry e, DateTime day) {
  final rec = e.recurrence;
  if (e.type != 'todo' || rec == null || e.dueAt == null) return false;
  final d = DateTime(day.year, day.month, day.day);
  if (!d.isAfter(_dayOf(e.dueAt!))) return false;
  final due = DateTime.fromMillisecondsSinceEpoch(e.dueAt!);
  switch (rec) {
    case 'daily':
      return true;
    case 'weekly':
      final set = (e.recurrenceDays == null || e.recurrenceDays!.isEmpty)
          ? <int>{due.weekday}
          : Set<int>.of(e.recurrenceDays!);
      return set.contains(d.weekday);
    case 'monthly':
      final dom = (e.monthDay == null || e.monthDay! < 1) ? due.day : e.monthDay!;
      final last = DateTime(d.year, d.month + 1, 0).day;
      return d.day == (dom > last ? last : dom);
    default:
      return false;
  }
}

/// Start of the calendar day of [ms] (local time).
DateTime _dayOf(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month, d.day);
}

/// The occurrence of a recurring [e] that belongs to TODAY or, when today
/// is not a task day (weekly / monthly), the first one after today. Keeps
/// the clock time of the current deadline. Catches up over any number of
/// missed periods. Returns epoch millis (unchanged dueAt when the current
/// deadline is already today or later).
int currentOccurrence(Entry e, DateTime now) {
  final rec = e.recurrence!;
  final due = e.dueAt!;
  final todayStart = DateTime(now.year, now.month, now.day);
  if (!_dayOf(due).isBefore(todayStart)) return due;
  final dueDt = DateTime.fromMillisecondsSinceEpoch(due);
  if (rec == 'daily') {
    // Every calendar day is an occurrence — today's is always the current.
    return DateTime(now.year, now.month, now.day, dueDt.hour, dueDt.minute)
        .millisecondsSinceEpoch;
  }
  // Pin the month day for the whole catch-up: without it a clamped
  // Feb 28 would drift every later month to the 28th.
  final monthDay = e.monthDay ?? dueDt.day;
  var next = due;
  var guard = 0;
  while (_dayOf(next).isBefore(todayStart) && guard++ < 5000) {
    next = nextOccurrence(
      recurrence: rec,
      days: e.recurrenceDays,
      monthDay: monthDay,
      fromMs: next,
      after: DateTime.fromMillisecondsSinceEpoch(next),
    );
  }
  return next;
}

/// "Skip this time": the shown occurrence is dropped without being done
/// and the task moves on, unchecked. An overdue one (past day) is skipped
/// to the current occurrence (today / next task day); today's or a future
/// one to the occurrence after it. Returns the new deadline, or null when
/// [e] is not a recurring task with a deadline.
int? skipRecurringOccurrence(Entry e, DateTime now) {
  if (e.recurrence == null || e.dueAt == null) return null;
  final cur = currentOccurrence(e, now);
  final curDt = DateTime.fromMillisecondsSinceEpoch(cur);
  final next = cur != e.dueAt ? cur : nextOccurrence(
    recurrence: e.recurrence!,
    days: e.recurrenceDays,
    monthDay: e.monthDay ?? curDt.day,
    fromMs: cur,
    after: curDt,
  );
  e.dueAt = next;
  e.updatedAt = DateTime.now().millisecondsSinceEpoch;
  for (final i in e.items ?? const <TodoItem>[]) {
    i.done = false;
  }
  return next;
}

void _reopen(Entry e, int dueAt) {
  e.dueAt = dueAt;
  e.updatedAt = DateTime.now().millisecondsSinceEpoch;
  // Kanban: a fresh occurrence starts in the first column — it used to stay
  // in "Done" with unchecked items.
  e.boardId = null;
  for (final i in e.items!) {
    i.done = false;
  }
}

bool _allDone(Entry e) {
  final items = e.items;
  return items != null && items.isNotEmpty && items.every((i) => i.done);
}

/// Pure recurrence reset pass over [entries] (no side effects beyond the
/// entries themselves). Every recurring period is a CALENDAR DAY: a task
/// checked for its day stays checked until 00:00, then the next occurrence
/// opens unchecked. Returns the entries that were reset.
///
/// * daily   — today's occurrence opens (same clock time, even if that
///             moment already passed: it is still today's task, never
///             skipped to tomorrow).
/// * weekly  — opens on the next selected weekday; on non-task days the
///             checkmark of the last occurrence holds.
/// * monthly — the next month's occurrence opens right after the due day.
List<Entry> rolloverRecurringTasks(List<Entry> entries, DateTime now) {
  final rolled = <Entry>[];
  final todayStart = DateTime(now.year, now.month, now.day);
  for (final e in entries) {
    if (e.recurrence == null || e.dueAt == null || !_allDone(e)) continue;
    if (!_dayOf(e.dueAt!).isBefore(todayStart)) continue; // today/future: hold
    if (e.recurrence == 'weekly') {
      // Not a task day yet: hold the checkmark until the next selected
      // weekday arrives (unless one was already missed — then reopen).
      final first = nextOccurrence(
        recurrence: 'weekly',
        days: e.recurrenceDays,
        fromMs: e.dueAt!,
        after: DateTime.fromMillisecondsSinceEpoch(e.dueAt!),
      );
      if (_dayOf(first).isAfter(todayStart)) continue;
    }
    _reopen(e, currentOccurrence(e, now));
    rolled.add(e);
  }
  return rolled;
}

/// Called right after a recurring task was completed. When the completed
/// occurrence belongs to a PAST day (overdue leftover), only that past
/// occurrence is closed: the task immediately reopens, unchecked, for
/// today (or the next task day). Completing yesterday's task must never
/// consume today's — a daily task exists every day.
///
/// Completing today's (or a future) occurrence changes nothing here: the
/// checkmark holds until the 00:00 rollover.
/// Returns true when the entry was reopened.
bool snapCompletedRecurring(Entry e, DateTime now) {
  if (e.recurrence == null || e.dueAt == null || !_allDone(e)) return false;
  final todayStart = DateTime(now.year, now.month, now.day);
  if (!_dayOf(e.dueAt!).isBefore(todayStart)) return false;
  _reopen(e, currentOccurrence(e, now));
  return true;
}