import 'dart:async';

import 'reminders.dart';
import 'media.dart';
import 'app_model.dart';
import 'models.dart';

/// Telegram-style "Deleted / Undo" for entries. Media files are moved to a
/// trash folder (they may be shared with forwarded copies) and the entries
/// are kept in memory until the undo window closes — nothing is lost if the
/// user taps Undo, nothing leaks if they don't ([MediaStore.purgeTrash]
/// cleans abandoned files on later launches).
class UndoService {
  /// Removes [entries] from state (with alarm cancel + media soft-remove).
  /// Returns true when anything was removed.
  static Future<bool> deleteEntries(AppModel model, List<Entry> entries) async {
    if (entries.isEmpty) return false;
    final ids = entries.map((e) => e.id).toSet();
    for (final e in entries) {
      await MediaStore().softRemove(e.media);
      try {
        await RemindersService.instance.cancelById(stableHash(e.id));
      } catch (_) {}
    }
    model.state.entries.removeWhere((e) => ids.contains(e.id));
    await model.save();
    return true;
  }

  /// Puts previously deleted entries back and restores their media.
  static Future<void> restoreEntries(AppModel model, List<Entry> entries) async {
    if (entries.isEmpty) return;
    for (final e in entries) {
      // Skip if an identical entry reappeared meanwhile (widget/sync).
      if (model.state.entries.any((x) => x.id == e.id)) continue;
      await MediaStore().restore(e.media);
      model.state.entries.add(e);
    }
    await model.save();
    unawaited(model.rescheduleAlarms());
  }
}
