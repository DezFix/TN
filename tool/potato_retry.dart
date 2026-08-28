#!/usr/bin/env dart
// Potato PC retry wrapper: runs a command, kills if hangs, retries 3 times.
// Usage: dart tool/potato_retry.dart -- flutter build apk --release
//        dart tool/potato_retry.dart -- flutter build windows --release
// If hangs (no stdout/stderr for 90s), kills and retries. After 3 fails, exits 1 with error.
import 'dart:async';
import 'dart:io';

void main(List<String> args) async {
  final sep = args.indexOf('--');
  final cmd = sep >= 0 ? args.sublist(sep + 1) : args;
  if (cmd.isEmpty) {
    stderr.writeln('Usage: dart tool/potato_retry.dart -- <command> [args...]');
    exit(2);
  }
  const maxRetries = 3;
  const hangTimeout = Duration(seconds: 90);
  for (var attempt = 1; attempt <= maxRetries; attempt++) {
    stdout.writeln('[potato] attempt $attempt/$maxRetries: ${cmd.join(' ')}');
    final proc = await Process.start(cmd[0], cmd.sublist(1), runInShell: true);
    var lastOutput = DateTime.now();
    var hangTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(lastOutput) > hangTimeout) {
        stderr.writeln('[potato] hang detected (>90s no output), killing PID ${proc.pid}');
        proc.kill(ProcessSignal.sigkill);
      }
    });
    // Forward output and track lastOutput
    proc.stdout.listen((data) {
      lastOutput = DateTime.now();
      stdout.add(data);
    });
    proc.stderr.listen((data) {
      lastOutput = DateTime.now();
      stderr.add(data);
    });
    final code = await proc.exitCode;
    hangTimer.cancel();
    if (code == 0) {
      stdout.writeln('[potato] success on attempt $attempt');
      exit(0);
    }
    stderr.writeln('[potato] failed with exit $code (attempt $attempt)');
    if (attempt == maxRetries) {
      stderr.writeln('[potato] ERROR: command "${cmd.join(' ')}" failed after $maxRetries attempts - stopping whole script');
      exit(code);
    }
    await Future.delayed(const Duration(seconds: 3));
    stdout.writeln('[potato] retrying...');
  }
}
