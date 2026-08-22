import 'package:audioplayers/audioplayers.dart';

/// Short UI sounds (task done "ding", etc.).
class Sounds {
  static final AudioPlayer _player = AudioPlayer();

  /// Played when a task item is marked as done — in-app or from the widget.
  static Future<void> taskDone() async {
    try {
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.stop();
      await _player.play(AssetSource('sounds/tn_ding.wav'), volume: 0.8);
    } catch (_) {
      // audio not available (tests, desktop) — ignore
    }
  }
}
