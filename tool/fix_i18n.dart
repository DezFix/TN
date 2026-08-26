// One-off repair script: restores Cyrillic/accented i18n values that were
// corrupted by shell-level string operations (double-encoded UTF-8), and
// re-inserts keys lost when multi-key lines were truncated.
// Run: dart run tool/fix_i18n.dart
//
// NOTE on packed lines: month_1..12 live three-per-line. The fix for
// 'month_1' therefore carries the WHOLE remainder of the packed line as its
// value — replacing the line restores every sibling at once.
import 'dart:io';

String _pack(Map<int, String> months) {
  final parts = <String>[];
  for (var i = 2; i <= 12; i++) {
    parts.add("'month_$i': '${months[i]}'");
  }
  return parts.join(', ') + ',';
}

final ruMonths = {
  1: 'января', 2: 'февраля', 3: 'марта', 4: 'апреля', 5: 'мая', 6: 'июня',
  7: 'июля', 8: 'августа', 9: 'сентября', 10: 'октября', 11: 'ноября',
  12: 'декабря',
};
final ukMonths = {
  1: 'січня', 2: 'лютого', 3: 'березня', 4: 'квітня', 5: 'травня',
  6: 'червня', 7: 'липня', 8: 'серпня', 9: 'вересня', 10: 'жовтня',
  11: 'листопада', 12: 'грудня',
};
final deMonths = {
  1: 'Januar', 2: 'Februar', 3: 'März', 4: 'April', 5: 'Mai', 6: 'Juni',
  7: 'Juli', 8: 'August', 9: 'September', 10: 'Oktober', 11: 'November',
  12: 'Dezember',
};
final esMonths = {
  1: 'de enero', 2: 'de febrero', 3: 'de marzo', 4: 'de abril', 5: 'de mayo',
  6: 'de junio', 7: 'de julio', 8: 'de agosto', 9: 'de septiembre',
  10: 'de octubre', 11: 'de noviembre', 12: 'de diciembre',
};
final frMonths = {
  1: 'janvier', 2: 'février', 3: 'mars', 4: 'avril', 5: 'mai', 6: 'juin',
  7: 'juillet', 8: 'août', 9: 'septembre', 10: 'octobre', 11: 'novembre',
  12: 'décembre',
};

final fixes = <String, Map<String, String>>{
  'en': {
    'hide_done': 'Hide done tasks',
  },
  'ru': {
    'month_1': _pack(ruMonths),
    'search_in_chat': 'Поиск в чате',
    'notifications_on': 'Уведомления включены',
    'notifications_off': 'Уведомления выключены',
    'todo_all_done': 'Выполнено ✓',
    'rss_only_channel': 'Только канал — пишет RSS',
    'rss_refresh': 'Обновить',
    'chat_deleted': 'Чат удалён',
    'tags_title': 'Теги',
    'tags_hint': 'Все #теги и количество записей',
    'agenda_title': 'Ближайшие задачи',
    'undo': 'Вернуть',
    'snoozed_to': 'Напомню через {}',
    'sched_monthly_day': 'Каждый месяц, число',
    'hide_done': 'Скрыть выполненные',
    'show_done': 'Показать выполненные',
    'tomorrow': 'Завтра',
    'lock_enable': 'Блокировка по биометрии',
    'lock_hint': 'Запрашивать отпечаток/PIN при входе в приложение',
    'lock_title': 'Разблокировать TN',
    'lock_failed': 'Не разблокировано',
    'bk_encrypt': 'Шифрование бэкапов',
    'bk_encrypt_hint':
        'Пароль шифрует локальные и облачные копии (AES-256-GCM). Без него восстановить нельзя — не теряйте.',
    'bk_pass_prompt': 'Бэкап зашифрован. Введите пароль:',
    'bk_wrong_pass': 'Неверный пароль или файл повреждён',
    'bk_pass_field': 'Пароль (необязательно)',
    'update_reinstall':
        'Установка не удалась. Если повторится — удалите приложение один раз и поставьте заново: сборка на устройстве подписана другим ключом.',
    'lock_methods': 'МЕТОД БЛОКИРОВКИ',
    'lock_method_biometric': 'Биометрия',
    'lock_method_pattern': 'Графический ключ',
    'lock_method_pin': 'ПИН-код',
    'lock_method_biometric_sub': 'Отпечаток или лицо устройства',
    'lock_method_pattern_sub': 'Рисунок из точек 3×3',
    'lock_method_pin_sub': 'Цифровой код 4–8 знаков',
    'lock_relock': 'ПОВТОРНАЯ БЛОКИРОВКА',
    'lock_relock_hint': 'Сколько держать приложение разблокированным',
    'lock_relock_now': 'Сразу',
    'lock_relock_5': '5 минут',
    'lock_relock_10': '10 минут',
    'lock_set_pin': 'Задайте ПИН-код',
    'lock_confirm_pin': 'Повторите ПИН-код',
    'lock_draw_pattern': 'Нарисуйте графический ключ',
    'lock_confirm_pattern': 'Повторите рисунок',
    'lock_mismatch': 'Не совпадает — попробуйте ещё раз',
    'lock_too_short': 'Минимум 4 точки',
    'lock_enter_pin': 'Введите ПИН-код',
    'lock_draw_unlock': 'Нарисуйте графический ключ',
    'lock_wrong': 'Неверный код',
    'lock_saved': 'Блокировка настроена',
  },
  'uk': {
    'month_1': _pack(ukMonths),
    'search_in_chat': 'Пошук у чаті',
    'notifications_on': 'Сповіщення увімкнено',
    'notifications_off': 'Сповіщення вимкнено',
    'todo_all_done': 'Виконано ✓',
    'rss_only_channel': 'Лише канал — пише RSS',
    'rss_refresh': 'Оновити',
    'chat_deleted': 'Чат видалено',
    'tags_title': 'Теги',
    'tags_hint': 'Усі #теги та кількість записів',
    'agenda_title': 'Найближчі задачі',
    'undo': 'Повернути',
    'snoozed_to': 'Нагадаю через {}',
    'sched_monthly_day': 'Щомісяця, число',
    'hide_done': 'Приховати виконані',
    'show_done': 'Показати виконані',
    'tomorrow': 'Завтра',
    'lock_enable': 'Блокування за біометрією',
    'lock_hint': 'Вимагати відбиток/PIN під час входу в додаток',
    'lock_title': 'Розблокувати TN',
    'lock_failed': 'Не розблоковано',
    'bk_encrypt': 'Шифрування бекапів',
    'bk_encrypt_hint':
        'Пароль шифрує локальні та хмарні копії (AES-256-GCM). Без нього відновити неможливо — не втрачайте.',
    'bk_pass_prompt': 'Бекап зашифровано. Введіть пароль:',
    'bk_wrong_pass': 'Неправильний пароль або файл пошкоджено',
    'bk_pass_field': "Пароль (необов'язково)",
    'update_reinstall':
        'Не вдалося встановити. Якщо повториться — видаліть додаток один раз і поставте знову: збірка на пристрої підписана іншим ключем.',
    'lock_methods': 'МЕТОД БЛОКУВАННЯ',
    'lock_method_biometric': 'Біометрія',
    'lock_method_pattern': 'Графічний ключ',
    'lock_method_pin': 'ПІН-код',
    'lock_method_biometric_sub': 'Відбиток або обличчя пристрою',
    'lock_method_pattern_sub': 'Малюнок із точок 3×3',
    'lock_method_pin_sub': 'Цифровий код 4–8 знаків',
    'lock_relock': 'ПОВТОРНЕ БЛОКУВАННЯ',
    'lock_relock_hint': 'Скільки тримати додаток розблокованим',
    'lock_relock_now': 'Одразу',
    'lock_relock_5': '5 хвилин',
    'lock_relock_10': '10 хвилин',
    'lock_set_pin': 'Задайте ПІН-код',
    'lock_confirm_pin': 'Повторіть ПІН-код',
    'lock_draw_pattern': 'Намалюйте графічний ключ',
    'lock_confirm_pattern': 'Повторіть малюнок',
    'lock_mismatch': 'Не збігається — спробуйте ще',
    'lock_too_short': 'Мінімум 4 точки',
    'lock_enter_pin': 'Введіть ПІН-код',
    'lock_draw_unlock': 'Намалюйте графічний ключ',
    'lock_wrong': 'Неправильний код',
    'lock_saved': 'Блокування налаштовано',
  },
  'de': {
    'month_1': _pack(deMonths),
    'hide_done': 'Erledigte ausblenden',
    'month_3': 'März',
    'sched_monthly_day': 'Jeden Monat am Tag.',
    'lock_method_biometric_sub': 'Geräte-Fingerabdruck oder Gesicht',
    'lock_relock_now': 'Sofort',
    'bk_encrypt_hint':
        'Ein Passwort verschlüsselt lokale und Cloud-Kopien (AES-256-GCM). Ohne es ist keine Wiederherstellung möglich.',
    'update_reinstall':
        'Installation fehlgeschlagen. Falls es wiederholt passiert — App einmal deinstallieren und neu installieren: die installierte Version ist anders signiert.',
    'lock_methods': 'SPERRMETHODE',
  },
  'es': {
    'month_1': _pack(esMonths),
    'hide_done': 'Ocultar hechas',
    'month_2': 'de febrero',
    'month_3': 'de marzo',
    'tomorrow': 'Mañana',
    'bk_encrypt_hint':
        'Una contraseña cifra las copias locales y en la nube (AES-256-GCM). Sin ella no se pueden restaurar.',
    'bk_pass_prompt': 'Esta copia está cifrada. Introduce la contraseña:',
    'bk_wrong_pass': 'Contraseña incorrecta o archivo dañado',
    'update_reinstall':
        'Fallo al instalar. Si se repite — desinstala la app una vez y reinstálala: la copia instalada usa otra firma.',
    'lock_method_pattern_sub': 'Patrón de puntos 3×3',
  },
  'fr': {
    'month_1': _pack(frMonths),
    'hide_done': 'Masquer les tâches faites',
    'month_2': 'février',
    'month_3': 'mars',
    'lock_hint': "Demander empreinte/PIN à l'ouverture de l'app",
    'bk_encrypt_hint':
        'Un mot de passe chiff les copies locales et cloud (AES-256-GCM). Sans lui, restauration impossible.',
    'bk_pass_prompt': 'Cette sauvegarde est chiffrée. Entrez le mot de passe :',
    'bk_wrong_pass': 'Mot de passe erroné ou fichier endommagé',
    'update_reinstall':
        "Échec de l'installation. Si cela se répète — désinstallez puis réinstallez une fois : signature différente.",
    'lock_method_biometric_sub': "Empreinte ou visage de l'appareil",
    'lock_relock_hint': "Durée pendant laquelle l'app reste déverrouillée",
  },
};

void main() {
  final file = File('lib/src/i18n.dart');
  var src = file.readAsStringSync();

  final blockRe = RegExp(r"^  '(\w{2})': \{", multiLine: true);
  final matches = blockRe.allMatches(src).toList();
  var repaired = 0;
  final missing = <String>[];

  // Process blocks bottom-up so earlier offsets stay valid while splicing.
  for (var b = matches.length - 1; b >= 0; b--) {
    final m = matches[b];
    final lang = m.group(1)!;
    final langFixes = fixes[lang];
    if (langFixes == null || langFixes.isEmpty) continue;
    final blockEnd =
        b + 1 < matches.length ? matches[b + 1].start : src.length;
    var block = src.substring(m.end, blockEnd);

    for (final entry in langFixes.entries) {
      final key = entry.key;
      final value = entry.value.replaceAll("'", r"\'");
      final newline = "'$key': '$value',";

      // Whole-line match (works for single-key lines).
      final lineRe = RegExp(
          "^\\s*'" + RegExp.escape(key) + "': .*?,\\s*\$",
          multiLine: true);
      final lineMatch = lineRe.firstMatch(block);
      if (lineMatch != null) {
        final leading = RegExp(r'^\s*')
            .firstMatch(block.substring(lineMatch.start))!
            .group(0)!;
        block =
            block.replaceRange(lineMatch.start, lineMatch.end, leading + newline);
        repaired++;
        continue;
      }

      // Key present somewhere mid-line? Then leave it alone unless it is one
      // of our known-bad packed owners handled above.
      if (block.contains("'$key':")) continue;

      // Absent entirely → insert before the block's closing brace.
      final closing = block.lastIndexOf('},');
      if (closing < 0) {
        missing.add('[$lang] $key (no closing brace)');
        continue;
      }
      block = block.substring(0, closing) + newline + '\n  ' + block.substring(closing);
      repaired++;
    }

    src = src.replaceRange(m.end, blockEnd, block);
  }

  file.writeAsStringSync(src);
  stdout.writeln('repaired: $repaired');
  if (missing.isNotEmpty) {
    for (final m in missing) {
      stderr.writeln('MISSING $m');
    }
    exitCode = 1;
  }
}
