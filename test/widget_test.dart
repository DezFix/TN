import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/main.dart';
import 'package:tn/screens/chat_screen.dart';
import 'package:tn/screens/list_screen.dart';
import 'package:tn/screens/widget_settings_screen.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';
import 'package:tn/src/widgets.dart';

void mockPlatformChannels({void Function(MethodCall)? onWidgetCall}) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter_timezone'),
    (call) async => 'UTC',
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('tn/widget'),
    (call) async {
      onWidgetCall?.call(call);
      return null;
    },
  );
}

void main() {
  testWidgets('app boots and shows empty state', (tester) async {
    SharedPreferences.setMockInitialValues({'tn-welcome-done': true});
    mockPlatformChannels();
    await tester.pumpWidget(const TN());
    await tester.pumpAndSettle();
    expect(find.byType(ListScreen), findsOneWidget);
  });

  testWidgets('list shows chats; search finds entries', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'Идеи', color: '#2AABEE'));
    state.entries.add(Entry(
        id: 'e1',
        chatId: 'c1',
        type: 'text',
        ts: DateTime.now().millisecondsSinceEpoch,
        text: 'привет #важно'));
    final model = AppModel(state: state);
    await tester.pumpWidget(MaterialApp(home: ListScreen(model: model)));

    expect(find.text('Идеи'), findsOneWidget);
    expect(find.text('привет #важно'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'важно');
    await tester.pump();
    expect(find.byType(SearchResultRow), findsOneWidget);
  });

  testWidgets('chat screen: send text adds entry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'Идеи', color: '#2AABEE'));
    final model = AppModel(state: state);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(model: model, chatId: 'c1'),
    ));

    await tester.enterText(find.byType(TextField), 'тест #важно');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(state.entries.length, 1);
    expect(state.entries.single.tags, ['важно']);
    expect(find.text('тест #важно'), findsOneWidget);
  });

  testWidgets('chat screen: todo bubble renders', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'Идеи', color: '#2AABEE'));
    state.entries.add(Entry(
        id: 'e1',
        chatId: 'c1',
        type: 'todo',
        ts: DateTime.now().millisecondsSinceEpoch,
        items: [
          TodoItem(id: 't1', text: 'купить молоко', done: false),
          TodoItem(id: 't2', text: 'позвонить', done: true),
        ]));
    final model = AppModel(state: state);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(model: model, chatId: 'c1'),
    ));

    expect(find.text('купить молоко'), findsOneWidget);
    expect(find.text('позвонить'), findsOneWidget);
  });

  testWidgets('chat screen: waveform bubble renders', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'Идеи', color: '#2AABEE'));
    final now = DateTime.now().millisecondsSinceEpoch;
    state.entries.add(Entry(
        id: 'e1',
        chatId: 'c1',
        type: 'text',
        ts: now,
        text: 'напоминание о деле'));
    state.entries.add(Entry(
        id: 'e2',
        chatId: 'c1',
        type: 'audio',
        ts: now,
        media: 'a.m4a',
        duration: 7,
        waveform: List<int>.generate(40, (i) => (i * 2) % 100)));
    final model = AppModel(state: state);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(model: model, chatId: 'c1'),
    ));

    expect(find.text('напоминание о деле'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // Telegram-style duration label under the waves.
    expect(find.text('0:07 ${model.tr('sec')}'), findsOneWidget);
    // Regression: waves must actually occupy width (Stack used to collapse
    // the waveform CustomPaint to Size(0, 30), leaving an empty bubble).
    await tester.pump();
    final waveSizes = find
        .byType(CustomPaint)
        .evaluate()
        .where((e) =>
            '${(e.widget as CustomPaint).painter.runtimeType}' ==
            '_WaveformPainter')
        .map((e) => (e.renderObject! as RenderBox).size)
        .toList();
    expect(waveSizes, isNotEmpty, reason: 'no waveform painted at all');
    for (final s in waveSizes) {
      expect(s.width, greaterThan(10), reason: 'waveform has zero width: $s');
    }
  });

  testWidgets('deep-link jump reaches far unbuilt entries', (tester) async {
    // Regression: tapping a calendar day (or a widget row) silently did
    // nothing when the target row wasn't built yet by the lazy list.
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'Дневник', color: '#2AABEE'));
    final base = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 40; i++) {
      state.entries.add(Entry(
          id: 'e$i',
          chatId: 'c1',
          type: 'text',
          ts: base - i * 3600000,
          text: 'msg $i'));
    }
    final model = AppModel(state: state);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
          model: model,
          chatId: 'c1',
          scrollToEntryId: 'e39',
          highlightEntryId: 'e39'),
    ));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('msg 39'));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.top, lessThan(600));
    // Let the 3s highlight timer finish so the test can tear down cleanly.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('widget settings binds kanban widget to a chat',
      (tester) async {
    var updates = 0;
    SharedPreferences.setMockInitialValues({
      'tn-kanbanwidget-chatId': 'k1',
    });
    mockPlatformChannels(
      onWidgetCall: (call) {
        if (call.method == 'update') updates++;
      },
    );
    final state = AppState();
    state.chats.addAll([
      Chat(id: 'k1', name: 'Доска 1', color: '#2AABEE', kind: 'kanban'),
      Chat(id: 'k2', name: 'Доска 2', color: '#E17055', kind: 'kanban'),
      Chat(id: 'n1', name: 'Обычный чат', color: '#00C853'),
      Chat(
        id: 'k3',
        name: 'Удалённая доска',
        color: '#6C5CE7',
        kind: 'kanban',
        deletedAt: 1,
      ),
    ]);
    final model = AppModel(state: state);
    await tester.pumpWidget(
      MaterialApp(home: WidgetSettingsScreen(model: model)),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('kanban-widget-chat-selector'));
    await tester.scrollUntilVisible(selector, 250);
    expect(find.text('Доска 1'), findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('kanban-widget-chat-k1')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-widget-chat-k2')), findsOneWidget);
    expect(find.text('Обычный чат'), findsNothing);
    expect(find.text('Удалённая доска'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('kanban-widget-chat-k2')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tn-kanbanwidget-chatId'), 'k2');
    expect(updates, 1);
    expect(find.text('Доска 2'), findsOneWidget);

    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kanban-widget-chat-all')));
    await tester.pumpAndSettle();
    expect(prefs.getString('tn-kanbanwidget-chatId'), isEmpty);
    expect(updates, 2);
  });

  testWidgets('widget settings explains when no kanban chat exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'tn-kanbanwidget-chatId': 'missing',
    });
    mockPlatformChannels();
    final state = AppState();
    state.chats.add(Chat(id: 'n1', name: 'Заметки', color: '#2AABEE'));
    final model = AppModel(state: state);
    await tester.pumpWidget(
      MaterialApp(home: WidgetSettingsScreen(model: model)),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('kanban-widget-chat-selector'));
    await tester.scrollUntilVisible(selector, 250);
    expect(tester.widget<InkWell>(selector).onTap, isNull);
    expect(find.text('Создайте Kanban-чат, чтобы выбрать доску'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('tn-kanbanwidget-chatId'),
      isNull,
    );
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kanban-widget-chat-picker')), findsNothing);
  });

  testWidgets('kanban deep link selects the target column before filtering',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(
      id: 'k1',
      name: 'Доска',
      color: '#2AABEE',
      kind: 'kanban',
    ));
    state.entries.addAll([
      Entry(
        id: 'idea-entry',
        chatId: 'k1',
        type: 'text',
        ts: 2,
        text: 'idea card',
      ),
      Entry(
        id: 'done-entry',
        chatId: 'k1',
        type: 'text',
        ts: 1,
        text: 'done card',
        boardId: 'done',
      ),
    ]);
    final model = AppModel(state: state);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        model: model,
        chatId: 'k1',
        scrollToEntryId: 'done-entry',
        highlightEntryId: 'done-entry',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('done card'), findsOneWidget);
    expect(find.text('idea card'), findsNothing);
    expect(find.byKey(const ValueKey('kanban-tab-done')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('kanban-drag-handle-done-entry')),
      findsOneWidget,
    );
    expect(find.byType(LongPressDraggable<Entry>), findsOneWidget);
    expect(find.byType(DragTarget<Entry>), findsNWidgets(3));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('kanban drag handle moves a card to another column',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(
      id: 'k1',
      name: 'Доска',
      color: '#2AABEE',
      kind: 'kanban',
    ));
    state.entries.add(Entry(
      id: 'entry',
      chatId: 'k1',
      type: 'text',
      ts: 1,
      text: 'draggable card',
    ));
    final model = AppModel(state: state);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(model: model, chatId: 'k1'),
    ));
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey('kanban-drag-handle-entry'));
    final target = find.byKey(const ValueKey('kanban-tab-work'));
    expect(handle, findsOneWidget);
    expect(target, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.entries.single.boardId, 'work');
  });
}