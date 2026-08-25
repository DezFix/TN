import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_model.dart';
import 'dialogs.dart';
import 'media.dart';
import 'models.dart';

/// Receives content shared from other apps (Android ACTION_SEND) and files
/// it into a chat chosen by the user — or into a brand-new chat.
class ShareIn {
  static const _channel = MethodChannel('tn/share');
  static bool _initialized = false;
  static BuildContext Function()? _getContext;
  static void Function(String chatId, String? entryId)? _openChat;

  /// [getContext] must return a context that sits above the Navigator;
  /// [openChat] pushes the chat screen (used after saving the entry).
  static void init(
    AppModel model, {
    required BuildContext Function() getContext,
    required void Function(String chatId, String? entryId) openChat,
  }) {
    if (_initialized) return;
    _initialized = true;
    _getContext = getContext;
    _openChat = openChat;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare' && call.arguments is Map) {
        await handle(model, Map<String, Object?>.from(call.arguments as Map));
      }
      return null;
    });
    // Cold start: the intent arrived before Dart was ready.
    _channel.invokeMethod('getPending').then((v) async {
      if (v is Map) await handle(model, Map<String, Object?>.from(v));
    }).catchError((_) => null);
  }

  static Future<void> handle(AppModel model, Map<String, Object?> args) async {
    try {
      final text = (args['text'] as String?)?.trim();
      final path = args['path'] as String?;
      final name = args['name'] as String?;
      final mime = ((args['mime'] as String?) ?? '').toLowerCase();
      if ((text == null || text.isEmpty) && path == null) return;
      final ctx = _getContext?.call();
      if (ctx == null || !ctx.mounted) return;

      final chat = await showForwardDialog(ctx, model, allowNewChat: true);
      if (chat == null || !ctx.mounted) return;

      Entry entry;
      if (path != null && mime.startsWith('image/')) {
        final stored = await MediaStore().saveImage(path);
        entry = Entry(
          id: uid('e'),
          chatId: chat.id,
          type: 'image',
          ts: DateTime.now().millisecondsSinceEpoch,
          text: text ?? '',
          media: stored,
          mediaName: name ?? stored,
        );
      } else if (path != null && mime.startsWith('video/')) {
        final stored = await MediaStore().saveFile(path, 'vid');
        entry = Entry(
          id: uid('e'),
          chatId: chat.id,
          type: 'video',
          ts: DateTime.now().millisecondsSinceEpoch,
          text: text ?? '',
          media: stored,
          mediaName: name,
        );
      } else if (path != null) {
        final stored = await MediaStore().saveFile(path, 'file');
        final size = await File(path).length();
        entry = Entry(
          id: uid('e'),
          chatId: chat.id,
          type: 'doc',
          ts: DateTime.now().millisecondsSinceEpoch,
          text: text ?? '',
          media: stored,
          mediaName: name ?? stored,
          mediaSize: _fmtSize(size),
        );
      } else {
        entry = Entry(
          id: uid('e'),
          chatId: chat.id,
          type: 'text',
          ts: DateTime.now().millisecondsSinceEpoch,
          text: text ?? '',
          tags: extractTags(text ?? ''),
        );
      }
      model.state.entries.add(entry);
      await model.save();
      _openChat?.call(chat.id, entry.id);
      final ctx2 = _getContext?.call();
      if (ctx2 != null && ctx2.mounted) {
        ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(
          content: Text(model.tr('shared_into', [chat.name])),
          duration: const Duration(milliseconds: 2000),
        ));
      }
    } catch (_) {}
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}
