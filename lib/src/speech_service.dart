import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Локальный мини-ИИ голос → текст. Использует системный on-device
/// распознаватель (Android: Google on-device, iOS: Apple on-device).
/// Никаких сетевых запросов — работает офлайн, если установлены языковые пакеты.
class SpeechService {
  static final SpeechToText _stt = SpeechToText();
  static bool _initialized = false;
  static bool _available = false;

  static bool get isAvailable => _available;
  static bool get isListening => _stt.isListening;

  static String localeFor(String appLang) {
    switch (appLang) {
      case 'ru':
        return 'ru_RU';
      case 'uk':
        return 'uk_UA';
      case 'de':
        return 'de_DE';
      case 'es':
        return 'es_ES';
      case 'fr':
        return 'fr_FR';
      case 'en':
      default:
        return 'en_US';
    }
  }

  static Future<bool> init() async {
    if (_initialized) return _available;
    try {
      _available = await _stt.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      _initialized = true;
    } catch (_) {
      _available = false;
      _initialized = true;
    }
    return _available;
  }

  static Future<bool> hasPermission() async => await _stt.hasPermission;

  static Future<bool> startListening({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    final ok = await init();
    if (!ok) return false;
    try {
      // onDevice:true — форсируем офлайн-распознавание, где поддерживается.
      return await _stt.listen(
        onResult: (SpeechRecognitionResult r) => onResult(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          onDevice: true,
          cancelOnError: false,
          partialResults: true,
          autoPunctuation: true,
          localeId: localeId,
          listenFor: listenFor,
          pauseFor: pauseFor,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      if (_stt.isListening) await _stt.stop();
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      if (_stt.isListening) await _stt.cancel();
    } catch (_) {}
  }
}
