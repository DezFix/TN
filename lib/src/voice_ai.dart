import 'dart:io';

import 'package:flutter/foundation.dart';
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

  static Future<bool> isModelReady() async {
    try {
      final path = await _controller.getPath(WhisperModel.tiny);
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Проверяет и при необходимости качает модель tiny (~75MB). Первый раз требует сеть, далее офлайн.
  static Future<bool> ensureModelDownloaded() async {
    try {
      final path = await _controller.getPath(WhisperModel.tiny);
      if (File(path).existsSync()) return true;
      debugPrint('VoiceAi: downloading whisper tiny model...');
      await _controller.downloadModel(WhisperModel.tiny);
      final ok = File(path).existsSync();
      debugPrint('VoiceAi: model download ${ok ? "ok" : "failed"} -> $path');
      return ok;
    } catch (e) {
      debugPrint('VoiceAi ensureModel error: $e');
      return false;
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
    if (!await file.exists()) {
      debugPrint('VoiceAi: file not found $audioPath');
      return null;
    }
    try {
      // 1) Убедиться что модель есть (первый раз — скачает ~75MB)
      final modelOk = await ensureModelDownloaded();
      if (!modelOk) {
        debugPrint('VoiceAi: model not available, need internet for first download');
        return null;
      }
      // 2) Транскрибация
      final lang = whisperLangFor(appLang);
      debugPrint('VoiceAi: transcribe $audioPath lang=$lang');
      final res = await _controller.transcribe(
        model: WhisperModel.tiny,
        audioPath: audioPath,
        lang: lang,
        onProgress: onProgress != null ? (p) => onProgress(p) : null,
      );
      final text = res?.transcription.text.trim();
      debugPrint('VoiceAi: result="${text?.substring(0, (text.length > 80 ? 80 : text.length))}"');
      if (text == null || text.isEmpty) return null;
      if (text.contains('BLANK_AUDIO')) return null;
      return text;
    } catch (e, st) {
      debugPrint('VoiceAi transcribe error: $e\n$st');
      return null;
    }
  }

  static Future<void> cancel() async {
    // whisper_ggml не exposes cancel в этой версии — no-op, транскрибация прервётся при dispose
    return;
  }
}
