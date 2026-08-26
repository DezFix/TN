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
  });

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

  bool get isTrashed => deletedAt != null;

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
        autoCollect: j['autoCollect'] == null
            ? null
            : AutoCollect.fromJson(j['autoCollect'] as Map<String, dynamic>),
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
        if (autoCollect != null) 'autoCollect': autoCollect!.toJson(),
      };
}

class TodoItem {
  TodoItem({required this.id, required this.text, this.done = false, this.parentId});

  final String id;
  String text;
  bool done;

  /// Non-null when this item is a subtask of another item in the same entry.
  String? parentId;

  factory TodoItem.fromJson(Map<String, dynamic> j) => TodoItem(
        id: j['id'] as String? ?? '',
        text: j['text'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        parentId: j['pid'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        if (parentId != null) 'pid': parentId,
      };
}

/// Toggles [id] and cascades the new value over its whole subtree (checking
/// a parent checks its subtasks, unchecking unchecks them). Pure function —
/// mutates [items] in place, returns true when anything changed.
bool toggleTodoCascade(List<TodoItem> items, String id) {
  final target = items.where((i) => i.id == id).firstOrNull;
  if (target == null) return false;
  final value = !target.done;
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
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String chatId;
  final String type;
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

  bool get isEdited => editedAt != null;

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
        items: items
            ?.map((i) => TodoItem(
                id: i.id, text: i.text, done: i.done, parentId: i.parentId))
            .toList(),
        dueAt: dueAt,
        recurrence: recurrence,
        recurrenceDays:
            recurrenceDays == null ? null : List.of(recurrenceDays!),
        monthDay: monthDay,
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

  switch (recurrence) {
    case 'daily':
      do {
        cand = cand.add(const Duration(days: 1));
      } while (!cand.isAfter(after));
      break;
    case 'weekly':
      final set = (days == null || days.isEmpty)
          ? <int>{from.weekday}
          : Set<int>.of(days);
      do {
        cand = cand.add(const Duration(days: 1));
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
        cand = cand.add(const Duration(days: 1));
      } while (!cand.isAfter(after));
  }
  return cand.millisecondsSinceEpoch;
}

/// Pure recurrence reset pass over [entries] (no side effects beyond the
/// entries themselves). A recurring task whose items are all done stays
/// checked until its *next* occurrence arrives; then items go back to
/// undone and dueAt jumps forward, catching up over missed periods.
/// Returns the entries that were reset.
List<Entry> rolloverRecurringTasks(List<Entry> entries, DateTime now) {
  final rolled = <Entry>[];
  final todayStart = DateTime(now.year, now.month, now.day);
  for (final e in entries) {
    final rec = e.recurrence;
    if (rec == null || e.dueAt == null) continue;
    final items = e.items;
    if (items == null || items.isEmpty || !items.every((i) => i.done)) {
      continue;
    }
    final dueDt = DateTime.fromMillisecondsSinceEpoch(e.dueAt!);
    final dueDayStart = DateTime(dueDt.year, dueDt.month, dueDt.day);

    if (rec == 'daily') {
      // Daily: reset at the start of a new calendar day.
      if (!dueDayStart.isBefore(todayStart)) continue;
    } else {
      // Weekly/monthly: stay checked until the next matching occurrence.
      var next = nextOccurrence(
        recurrence: rec,
        days: e.recurrenceDays,
        monthDay: e.monthDay,
        fromMs: e.dueAt!,
        after: DateTime.fromMillisecondsSinceEpoch(e.dueAt!),
      );
      if (now.isBefore(DateTime.fromMillisecondsSinceEpoch(next))) continue;
    }

    // Catch up: find the next occurrence strictly after now.
    var next = nextOccurrence(
      recurrence: rec,
      days: e.recurrenceDays,
      monthDay: e.monthDay,
      fromMs: e.dueAt!,
      after: DateTime.fromMillisecondsSinceEpoch(e.dueAt!),
    );
    while (!DateTime.fromMillisecondsSinceEpoch(next).isAfter(now)) {
      next = nextOccurrence(
        recurrence: rec,
        days: e.recurrenceDays,
        monthDay: e.monthDay,
        fromMs: next,
        after: DateTime.fromMillisecondsSinceEpoch(next),
      );
    }
    e.dueAt = next;
    for (final i in items) {
      i.done = false;
    }
    rolled.add(e);
  }
  return rolled;
}

/// Called right after a recurring task was completed while OVERDUE (its
/// period already ended). For DAILY tasks the period is the CALENDAR DAY:
/// completing yesterday's leftover today snaps the deadline to *today*,
/// same clock time (even if that moment already passed) — the checkmark
/// then holds until tonight's 00:00 rollover, and the fresh instance is
/// always today's, never "the overdue one". Weekly/monthly keep snapping
/// to the next occurrence after [now].
/// Returns true when the entry changed.
bool snapCompletedRecurring(Entry e, DateTime now) {
    final rec = e.recurrence;
    if (rec == null || e.dueAt == null) return false;
    final items = e.items;
    if (items == null || items.isEmpty || !items.every((i) => i.done)) {
      return false;
    }
    if (DateTime.fromMillisecondsSinceEpoch(e.dueAt!).isAfter(now)) {
      return false; // not overdue — normal flow, nothing to snap
    }
    if (rec == 'daily') {
      final due = DateTime.fromMillisecondsSinceEpoch(e.dueAt!);
      e.dueAt =
          DateTime(now.year, now.month, now.day, due.hour, due.minute)
              .millisecondsSinceEpoch;
      return true;
    }
    e.dueAt = nextOccurrence(
      recurrence: rec,
      days: e.recurrenceDays,
      monthDay: e.monthDay,
      fromMs: e.dueAt!,
      after: now,
    );
    return true;
  }