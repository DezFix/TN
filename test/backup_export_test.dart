import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tn/src/backup.dart';
import 'package:tn/src/state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tn/backup');
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final name = (call.arguments as Map)['name'] as String;
      return 'Download/$name';
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('export on Android writes through the MediaStore channel', () async {
    final path = await BackupService.export(AppState());
    expect(path, startsWith('Download/tn-backup-'));
    final args = calls.single.arguments as Map;
    expect(calls.single.method, 'saveToDownloads');
    expect(args['name'], endsWith('.zip'));
    expect((args['bytes'] as Uint8List).isNotEmpty, isTrue);
    expect(args['keepMax'], 3);
  });

  test('auto backup runs on Android without a chosen folder', () async {
    SharedPreferences.setMockInitialValues({'tn-backup-days': 1});
    final path = await BackupService.maybeAutoBackup(AppState());
    expect(path, isNotNull);
    expect(calls.single.method, 'saveToDownloads');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('tn-backup-last'), isNotNull);
  });
}
