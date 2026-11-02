import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/chat_lock.dart';
import 'package:tn/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ChatLock.init();
  });

  test('chat lock persists and unlocks for the session only', () async {
    expect(ChatLock.isLocked('c1', null), isFalse);
    await ChatLock.setChat('c1', true);
    expect(ChatLock.isLocked('c1', null), isTrue);
    expect(ChatLock.isSessionUnlocked('c1', null), isFalse);

    ChatLock.markSessionUnlocked('c1', null);
    expect(ChatLock.isSessionUnlocked('c1', null), isTrue);

    // New process: session cache is gone, persisted lock stays.
    await ChatLock.init();
    expect(ChatLock.isLocked('c1', null), isTrue);
    expect(ChatLock.isSessionUnlocked('c1', null), isFalse);
  });

  test('folder lock covers chats and unlocks the whole folder', () async {
    await ChatLock.setFolder('f1', true);
    expect(ChatLock.isLocked('c9', 'f1'), isTrue);
    expect(ChatLock.isLocked('c9', 'f2'), isFalse);

    ChatLock.markSessionUnlocked('c9', 'f1');
    expect(ChatLock.isSessionUnlocked('c9', 'f1'), isTrue);
    expect(ChatLock.isSessionUnlocked('c8', 'f1'), isTrue);
  });

  test('chat createdAt falls back to the id timestamp', () {
    final chat = Chat(
      id: 'c-1700000000000000-ab12cd',
      name: 'old',
      color: '#FFFFFF',
    );
    expect(chat.createdAt, 1700000000000);
  });
}
