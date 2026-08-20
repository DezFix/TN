const storageKey = 'tn-notes-data-v1';
const mediaDirName = 'tn_media';

const appColors = [
  '#2AABEE', '#E0663E', '#7C5CD6', '#3EA66E',
  '#D6538B', '#C99A2E', '#5C7CFA', '#20B2AA',
];

const appIcons = <String?>[
  null, '💡', '📌', '💼', '🎯', '📚', '🎨', '🎧', '🍳', '✈️', '🌱', '⚡', '🧠', '❤️', '🏋️', '🎵',
];

class Chat {
  Chat({required this.id, required this.name, required this.color, this.icon});

  final String id;
  String name;
  String color;
  String? icon;

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        color: j['color'] as String? ?? appColors[0],
        icon: j['icon'] as String?,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color, 'icon': icon};
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