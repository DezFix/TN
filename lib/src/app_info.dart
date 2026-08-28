import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class AppInfo {
  static const _channel = MethodChannel('tn/appInfo');

  static Future<String> getAbi() async {
    if (!Platform.isAndroid) return 'universal';
    try {
      final abi = await _channel.invokeMethod<String>('getAbi');
      return abi ?? 'arm64-v8a';
    } catch (_) {
      return 'arm64-v8a';
    }
  }

  static Future<List<String>> getSupportedAbis() async {
    if (!Platform.isAndroid) return ['universal'];
    try {
      final list = await _channel.invokeMethod<List>('getSupportedAbis');
      if (list == null) return [await getAbi()];
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [await getAbi()];
    }
  }

  static Future<int> getVersionCode() async {
    if (!Platform.isAndroid) return 0;
    try {
      final v = await _channel.invokeMethod<int>('getVersionCode');
      return v ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> isUniversal() async {
    if (!Platform.isAndroid) return true;
    try {
      final v = await _channel.invokeMethod<bool>('isUniversal');
      return v ?? true;
    } catch (_) {
      // Fallback via versionCode heuristic: universal <1000
      final vc = await getVersionCode();
      return vc < 1000 || vc % 1000 == vc;
    }
  }

  /// Returns true if installed versionCode looks like a split (arm64/x86_64) that would downgrade if we install universal.
  static Future<bool> isSplitInstalled() async {
    final uni = await isUniversal();
    return !uni;
  }
}
