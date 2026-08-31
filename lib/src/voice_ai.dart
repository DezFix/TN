import 'dart:io';

import 'package:whisper_ggml/whisper_ggml.dart';

/// Локальный мини-ИИ для расшифровки голосовых сообщений в текст.
/// Работает полностью офлайн через whisper.cpp (tiny/base модели, ~75MB).
/// Никаких сетевых запросов после загрузки модели.
class VoiceAi {
  static final WhisperController _controller = WhisperController();

  /// Локаль приложения -> whisper lang код ('ru','en','uk'...)
  static String whisperLangFor(String appLang) {
    switch (appLang) {
      case 'ru':
        return 'ru';
      case 'uk':
        return 'uk';
      case 'de':
        return 'de';
      case 'es':
        return 'es';
      case 'fr':
        return 'fr';
      default:
        return 'en';
    }
  }

  /// Транскрибирует аудиофайл локально. Возвращает текст или null.
  /// `audioPath` — абсолютный путь к m4a/wav.
  static Future<String?> transcribeFile(
    String audioPath, {
    required String appLang,
    void Function(int progress)? onProgress,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) return null;
    try {
      // tiny — самая лёгкая, ~75MB, быстрая на телефоне. Для лучшего качества можно base.
      final lang = whisperLangFor(appLang);
      final res = await _controller.transcribe(
        model: WhisperModel.tiny,
        audioPath: audioPath,
        lang: lang,
        onProgress: onProgress != null ? (p) => onProgress(p) : null,
      );
      final text = res?.transcription.text.trim();
      if (text == null || text.isEmpty) return null;
      // Whisper иногда возвращает "[BLANK_AUDIO]" для тишины
      if (text.contains('BLANK_AUDIO')) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> cancel() async {
    // whisper_ggml не exposes cancel в этой версии — no-op, транскрибация прервётся при dispose
    return;
  }
}
