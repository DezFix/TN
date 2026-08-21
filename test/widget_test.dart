import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/main.dart';
import 'package:tn/screens/chat_screen.dart';
import 'package:tn/screens/list_screen.dart';
import 'package:tn/src/app_model.dart';
import 'package:tn/src/models.dart';
import 'package:tn/src/state.dart';
import 'package:tn/src/widgets.dart';

void mockPlatformChannels() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter_timezone'),
    (call) async => 'UTC',
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (call) async => null,
  );
}

void main() {
  testWidgets('app boots and shows empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockPlatformChannels();
    await tester.pumpWidget(const TN());
    await tester.pumpAndSettle();
    expect(find.byType(ListScreen), findsOneWidget);
    tester.widget<ListScreen>(find.byType(ListScreen)).model.stopScheduler();
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

  testWidgets('chat screen: scheduled entry shows clock badge and waveform bubble',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.chats.add(Chat(id: 'c1', name: 'Идеи', color: '#2AABEE'));
    final now = DateTime.now().millisecondsSinceEpoch;
    state.entries.add(Entry(
        id: 'e1',
        chatId: 'c1',
        type: 'text',
        ts: now,
        text: 'напоминание о деле',
        scheduledAt: now + 3600000));
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
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
  });
}