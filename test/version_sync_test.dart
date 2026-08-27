import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/app_update.dart';

/// Guards against the About screen showing a stale version: the constant in
/// app_update.dart must always match pubspec.yaml (they were drifting apart
/// because the About screen renders the constant, not the pubspec value).
void main() {
  test('appBuildVersion matches pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([^\s\+]+)\+', multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(appBuildVersion, m!.group(1),
        reason:
            'bump BOTH pubspec.yaml and appBuildVersion in src/app_update.dart');
  });
}
