import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/screens/about_screen.dart';
import 'package:tn/screens/chat_edit_screen.dart';
import 'package:tn/screens/folders_edit_screen.dart';
import 'package:tn/screens/lock_settings_screen.dart';
import 'package:tn/screens/tags_screen.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/theme.dart';
import 'package:tn/src/undo_toast.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';

/// Regression: ListTile under a colored DecoratedBox/ColoredBox hides its
/// ink splash (Bugsink: "ListTile background color or ink splashes may be
/// invisible"). Every ListTile on these screens must reach a Material
/// ancestor without crossing a colored box.
void expectTilesOnMaterial(WidgetTester tester) {
  final tiles = find.byType(ListTile).evaluate();
  expect(tiles, isNotEmpty, reason: 'expected ListTiles on screen');
  for (final e in tiles) {
    var clean = true;
    var hasMaterial = false;
    e.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      if (w is Material) {
        hasMaterial = true;
        return false; // stop: ink paints here
      }
      if (w is ColoredBox &&
          w.color != Colors.transparent) {
        clean = false;
      }
      if (w is DecoratedBox) {
        final d = w.decoration;
        if (d is BoxDecoration &&
            d.color != null &&
            d.color != Colors.transparent) {
          clean = false;
        }
      }
      return true;
    });
    expect(hasMaterial, isTrue, reason: 'ListTile without Material ancestor');
    expect(clean, isTrue,
        reason: 'ListTile hidden under a colored box: ${e.widget}');
  }
}

void main() {
  AppModel modelWithTag() {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'X', color: '#2AABEE'));
    state.entries.add(Entry(
      id: 'e1',
      chatId: 'c1',
      type: 'text',
      ts: 0,
      text: 'hello #tag',
      tags: const ['tag'],
    ));
    return AppModel(state: state);
  }

  testWidgets('tags screen tiles sit on Material', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TagsScreen(model: modelWithTag())));
    await tester.pump();
    expect(find.text('tag'), findsOneWidget);
    expectTilesOnMaterial(tester);
  });

  testWidgets('folders screen tiles sit on Material', (tester) async {
    final model = modelWithTag();
    model.state.folders.add(Folder(id: 'f1', name: 'Work'));
    await tester
        .pumpWidget(MaterialApp(home: FoldersEditScreen(model: model)));
    await tester.pump();
    expect(find.text('Work'), findsOneWidget);
    expectTilesOnMaterial(tester);
  });

  testWidgets('about screen tiles sit on Material', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AboutScreen(model: modelWithTag())));
    await tester.pump();
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    expectTilesOnMaterial(tester);
  });

  testWidgets('lock settings tiles sit on Material', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: LockSettingsScreen(model: modelWithTag())));
    await tester.pump();
    expectTilesOnMaterial(tester);
  });

  testWidgets('chat edit switch sits on Material', (tester) async {
    final model = modelWithTag();
    await tester.pumpWidget(MaterialApp(
        home: ChatEditScreen(
            model: model,
            chat: Chat(id: 'c1', name: 'X', color: '#2AABEE'))));
    await tester.pump();
    expectTilesOnMaterial(tester);
  });

  testWidgets('undo toast runs slide+ring without ticker assertion',
      (tester) async {
    // Regression for "_UndoToastViewState is a SingleTickerProviderStateMixin
    // but multiple tickers were created" (Bugsink): the toast owns a slide
    // AND a ring controller, so its State must mix in TickerProviderStateMixin.
    // On the old code this throws while pumping.
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    var undone = false;
    UndoToast.show(
      ctx,
      message: 'deleted-msg',
      actionLabel: 'undo-act',
      onUndo: () => undone = true,
      p: paletteFor('dark'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('deleted-msg'), findsOneWidget);
    expect(find.text('undo-act'), findsOneWidget);
    // Tap fires undo exactly once and closes (reverse animation needs frames).
    await tester.tap(find.text('undo-act'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('deleted-msg'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });
}
