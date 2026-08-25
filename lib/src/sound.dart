import 'package:audioplayers/audioplayers.dart';

/// Short UI sounds (task done "ding", etc.).
class Sounds {
  static final AudioPlayer _player = AudioPlayer();
  static bool _ctxSet = false;

  /// Played when a task item is marked as done — in-app or from the widget.
  static Future<void> taskDone() async {
    try {
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setReleaseMode(ReleaseMode.stop);
      // Set notification audio context on Android so the ding plays on the
      // notification stream (volume controlled by notification slider,
      // not media).
      if (!_ctxSet) {
        try {
          await _player.setAudioContext(AudioContext(
            android: const AudioContextAndroid(
              usageType: AndroidUsageType.notification,
              contentType: AndroidContentType.sonification,
            ),
          ));
          _ctxSet = true;
        } catch (_) {}
      }
      await _player.stop();
      await _player.play(AssetSource('sounds/tn_ding.wav'), volume: 0.8);
    } catch (_) {
      // audio not available (tests, desktop) — ignore
    }
  }
}
