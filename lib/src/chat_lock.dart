import 'package:shared_preferences/shared_preferences.dart';

/// Per-chat / per-folder lock. The data itself stays in SharedPreferences:
/// this is a UI gate backed by the app lock, not encryption.
///
/// Unlocks live in memory for the current app run; a restart asks again.
class ChatLock {
  static const _keyChats = 'tn-locked-chats';
  static const _keyFolders = 'tn-locked-folders';

  static Set<String> _chats = {};
  static Set<String> _folders = {};
  static final Set<String> _session = {};

  static Future<void> init() async {
    _session.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      _chats = (prefs.getStringList(_keyChats) ?? const []).toSet();
      _folders = (prefs.getStringList(_keyFolders) ?? const []).toSet();
    } catch (_) {}
  }

  static bool isChatLocked(String chatId) => _chats.contains(chatId);

  static bool isFolderLocked(String? folderId) =>
      folderId != null && _folders.contains(folderId);

  static bool isLocked(String chatId, String? folderId) =>
      isChatLocked(chatId) || isFolderLocked(folderId);

  static bool isSessionUnlocked(String chatId, String? folderId) =>
      _session.contains(chatId) ||
      (folderId != null && _session.contains('folder:$folderId'));

  static void markSessionUnlocked(String chatId, String? folderId) {
    _session.add(chatId);
    if (folderId != null) _session.add('folder:$folderId');
  }

  static Future<void> setChat(String chatId, bool locked) async {
    if (locked) {
      _chats.add(chatId);
    } else {
      _chats.remove(chatId);
    }
    if (!locked) _session.remove(chatId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyChats, _chats.toList());
    } catch (_) {}
  }

  static Future<void> setFolder(String folderId, bool locked) async {
    if (locked) {
      _folders.add(folderId);
    } else {
      _folders.remove(folderId);
    }
    if (!locked) _session.remove('folder:$folderId');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyFolders, _folders.toList());
    } catch (_) {}
  }

  /// Folder ids that are currently locked (for settings/tests).
  static Set<String> get lockedFolders => Set.of(_folders);

  /// Chat ids that are currently locked (for settings/tests).
  static Set<String> get lockedChats => Set.of(_chats);

  /// App lock was turned off: per-chat locks would be unpassable.
  static Future<void> clearAll() async {
    _chats.clear();
    _folders.clear();
    _session.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyChats);
      await prefs.remove(_keyFolders);
    } catch (_) {}
  }
}
