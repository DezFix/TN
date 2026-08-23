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
  Folder({required this.id, required this.name});

  final String id;
  String name;

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
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
        if (autoCollect != null) 'autoCollect': autoCollect!.toJson(),
      };
}

class TodoItem {
  TodoItem({required this.id, required this.text, this.done = false});

  final String id;
  String text;
  bool done;

  factory TodoItem.fromJson(Map<String, dynamic> j) => TodoItem(
        id: j['id'] as String? ?? '',
        text: j['text'] as String? ?? '',
        done: j['done'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
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
    this.dueAt,
    this.editedAt,
  });

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
  String? recurrence; // null | 'daily' | 'weekly'
  List<int>? recurrenceDays; // 1=Mon..7=Sun for weekly
  int? dueAt; // for tasks-chat todos: deadline millis
  int? editedAt; // millis when last edited

  bool get isEdited => editedAt != null;

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
        dueAt: (j['dueAt'] as num?)?.toInt(),
        editedAt: (j['editedAt'] as num?)?.toInt(),
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
        if (dueAt != null) 'dueAt': dueAt,
        if (editedAt != null) 'editedAt': editedAt,
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

String uid(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${(0xFFFF & DateTime.now().millisecond).toRadixString(16)}';