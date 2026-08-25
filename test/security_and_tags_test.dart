import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/gdrive.dart';
import 'package:tn/src/models.dart';
import 'package:tn/screens/agenda_screen.dart';
import 'package:tn/screens/tags_screen.dart';
import 'package:tn/src/state.dart';
import 'package:tn/src/updater.dart';

void main() {
  group('PKCE', () {
    test('verifier length and alphabet (RFC 7636)', () {
      final v = GoogleDriveClient.generateCodeVerifier();
      expect(v.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
      expect(GoogleDriveClient.generateCodeVerifier(), isNot(v));
    });

    test('S256 challenge matches the RFC 7636 appendix-B vector', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(GoogleDriveClient.codeChallengeS256(verifier),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });
  });

  group('verifySha256', () {
    test('empty input has the well-known digest', () {
      expect(
        verifySha256(const <int>[],
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
        isTrue,
      );
    });

    test('rejects wrong or malformed digests', () {
      expect(verifySha256(utf8.encode('hello'), 'deadbeef'), isFalse);
      expect(verifySha256(const <int>[], ''), isFalse);
    });
  });

  group('#tag search', () {
    AppState state() {
      final s = AppState();
      s.entries.add(Entry(id: 'a', chatId: 'c1', type: 'text', ts: 1, text: 'покупка'));
      s.entries.add(Entry(id: 'b', chatId: 'c1', type: 'text', ts: 2, text: 'план на день'));
      return s;
    }

    test("'#tag' restricts results to tag matches", () {
      final s = state()..entries[0].tags = ['еда'];
      expect(s.searchEntries('#еда').map((e) => e.id), ['a']);
      // A '#'-query never falls back to plain text matching.
      expect(s.searchEntries('#день'), isEmpty);
    });

    test('plain query still searches text and todo items', () {
      final s = state();
      s.entries.add(Entry(
          id: 'c',
          chatId: 'c1',
          type: 'todo',
          ts: 3,
          items: [TodoItem(id: 'i', text: 'позвонить')]));
      expect(s.searchEntries('день').map((e) => e.id), ['b']);
      expect(s.searchEntries('позвонить').map((e) => e.id), ['c']);
    });
  });

  group('tag manager aggregation', () {
    test('counts entries per tag across live chats only', () {
      final model = AppModel();
      final s = model.state;
      s.chats.add(Chat(id: 'c1', name: 'a', color: '#FFFFFF'));
      s.chats.add(Chat(id: 'c2', name: 'b', color: '#FFFFFF', deletedAt: 5));
      s.entries
          .add(Entry(id: 'e1', chatId: 'c1', type: 'text', ts: 1, text: '', tags: ['работа']));
      s.entries
          .add(Entry(id: 'e2', chatId: 'c1', type: 'text', ts: 2, text: '', tags: ['работа']));
      // Trashed chat entries are excluded.
      s.entries
          .add(Entry(id: 'e3', chatId: 'c2', type: 'text', ts: 3, text: '', tags: ['работа']));
      final tags = TagsScreen.collectTags(s);
      expect(tags['работа'], 2);
      expect(tags.length, 1);
    });
  });

  group('agenda grouping', () {
    test('undone dated todos group by day; overdue joins today', () {
      final now = DateTime.now();
      final model = AppModel();
      final s = model.state;
      s.chats.add(Chat(id: 'c1', name: 'a', color: '#FFFFFF'));
      final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final tomorrow = today + 86400000;
      s.entries.add(Entry(
          id: 'overdue',
          chatId: 'c1',
          type: 'todo',
          ts: 1,
          dueAt: today - 3 * 86400000,
          items: [TodoItem(id: 'i1', text: 'x')])); // undone -> groups into TODAY
      s.entries.add(Entry(
          id: 'done',
          chatId: 'c1',
          type: 'todo',
          ts: 2,
          dueAt: tomorrow,
          items: [TodoItem(id: 'i2', text: 'y', done: true)])); // fully done -> skipped
      s.entries.add(Entry(
          id: 'later',
          chatId: 'c1',
          type: 'todo',
          ts: 3,
          dueAt: tomorrow + 3600000,
          items: [TodoItem(id: 'i3', text: 'z')]));
      s.entries
          .add(Entry(id: 'note', chatId: 'c1', type: 'text', ts: 4, text: 'not a todo'));

      final groups = AgendaScreen.groupByDay(s, now);
      final keys = groups.keys.toList();
      expect(keys.first, today);
      expect(groups[keys.first]!.map((e) => e.id), ['overdue']);
      expect(groups[keys.last]!.map((e) => e.id), ['later']);
    });
  });
}
