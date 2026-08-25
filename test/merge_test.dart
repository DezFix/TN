import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';

AppState fromRaw(Map<String, dynamic> json) {
  final s = AppState();
  s.loadFromJson(jsonEncode(json));
  return s;
}

void main() {
  test('merge adds records missing locally', () {
    final local = AppState();
    local.chats.add(Chat(id: 'c1', name: 'local', color: '#FFFFFF'));
    local.mergeFromJson(jsonEncode({
      'chats': [
        {'id': 'c1', 'name': 'local', 'color': '#FFFFFF'},
        {'id': 'c2', 'name': 'remote-only', 'color': '#FF0000'},
      ],
      'entries': [
        {'id': 'e-remote', 'chatId': 'c1', 'type': 'text', 'ts': 5, 'text': 'hi'},
      ],
    }));
    expect(local.chats.length, 2);
    expect(local.entries.single.id, 'e-remote');
  });

  test('merge takes the newer entry by updatedAt (LWW)', () {
    final local = AppState();
    local.entries.add(Entry(
        id: 'e1', chatId: 'c1', type: 'text', ts: 1, text: 'old local', updatedAt: 100));
    local.mergeFromJson(jsonEncode({
      'entries': [
        {
          'id': 'e1',
          'chatId': 'c1',
          'type': 'text',
          'ts': 1,
          'text': 'newer remote',
          'updatedAt': 200
        },
      ],
    }));
    expect(local.entries.single.text, 'newer remote');

    // Older remote must NOT overwrite newer local.
    local.mergeFromJson(jsonEncode({
      'entries': [
        {
          'id': 'e1',
          'chatId': 'c1',
          'type': 'text',
          'ts': 1,
          'text': 'ancient remote',
          'updatedAt': 50
        },
      ],
    }));
    expect(local.entries.single.text, 'newer remote');
  });

  test('merge keeps local trashed state and never resurrects chats', () {
    final local = AppState();
    local.chats.add(Chat(id: 'c1', name: 'chat', color: '#FFFFFF'));
    local.chats.first.deletedAt = 999;
    local.mergeFromJson(jsonEncode({
      'chats': [
        {'id': 'c1', 'name': 'chat', 'color': '#FFFFFF'},
      ],
    }));
    expect(local.chats.single.isTrashed, isTrue);
  });

  test('merge does not clobber local theme/lang', () {
    final local = fromRaw({'theme': 'light', 'lang': 'de'});
    local.mergeFromJson(jsonEncode({'theme': 'dark', 'lang': 'ru'}));
    expect(local.theme, 'light');
    expect(local.lang, 'de');
  });
}
