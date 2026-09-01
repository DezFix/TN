# Changelog

All notable TN releases. The newest section is shown to users inside the
app ("What's new" dialog) — keep entries user-facing and concise.
Everything published here goes to GitHub in English only.

## [1.27.5] - 2026-08-31

- **Voice AI fix:** `whisper_ggml` теперь реально встроен и телефоном обрабатывается — добавлен `VoiceAi.isModelReady()/ensureModelDownloaded()` (`getPath` + `downloadModel` `tiny ~75MB`), первый раз показывает `Загрузка AI модели ~75MB — нужен интернет один раз` и `Модель загружена — расшифровываю локально`, далее офлайн; исправлен `недоступно` (ранее `speech_to_text` системный), улучшены `debugPrint` и `try/catch`, `cancel` no-op

## [1.27.4] - 2026-08-31

- **Build fix:** CI `Install NDK 29 for whisper_ggml` — теперь ставит обе `29.0.13113456` (требует `whisper_ggml` плагин) + `29.0.14206865` (app), через `$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager` + `yes | --licenses` до и после, чинит `FAILURE License not accepted` на `v1.27.2/v1.27.3` (android `whisper_ggml` `ndk;29.0.13113456` лицензия). Windows билд уже был `success`, android теперь тоже

## [1.27.3] - 2026-08-31

- **Build fix:** `ndkVersion 29.0.14206865` (stable) + CI `Install NDK 29` step (`sdkmanager --install ndk;29.0.14206865`, `yes | sdkmanager --licenses`) — чинит падение `Build APKs` `FAILURE License not accepted` на `v1.27.2` (`29.0.13113456 rc1` → stable). Локально установлено оба NDK, сборка `130.7MB` успешна `140s`

## [1.27.2] - 2026-08-31

- **Build:** `android/app/build.gradle.kts:32` `ndkVersion 29.0.13113456` для `whisper_ggml` (ранее `flutter.ndkVersion 27`), исправляет `LICENSE not accepted` / `NDK 29 required` на CI и локально; APK вырос `65.7MB → 130.7MB` из-за `whisper.cpp` native libs, но остаётся offline

## [1.27.1] - 2026-08-31

- **Voice AI fix:** кнопка ✨ перенесена с панели ввода на сам голосовой пузырь — `Расшифровать` прямо на сообщении; теперь всегда доступна (локальный `whisper_ggml` tiny, offline, `ru/en/uk/de/es/fr`), а не `недоступно` от системы. Показывает `LinearProgress` + `AI расшифровывает локально...`, превью текста, `Копировать` и `Как задачу/заметку` (сохраняет в текущий чат). Модель качается один раз и кэшируется, далее без сети. Composer-кнопка удалена

## [1.27.0] - 2026-08-31

- **Todo editor:** simplified per user feedback — now 2 clear menus: (1) tasks & subtasks only (input + list with `↳` subtasks, `✓` toggle, `×` delete) and (2) time & importance (tap `Изменить время` → existing date/time & priority sheet). Importance chips removed from the first sheet — priority lives only in the time sheet, as requested
- **Voice AI (NEW, local):** on-device speech-to-text (no internet) — tap ✨ in composer, dictate, see live transcription `↳ sub` preview, `Готово` saves as Task (in Tasks chats) or Note (in Notes chats). Uses `speech_to_text` with `onDevice:true`, `locale` from app language (`ru_RU/uk_UA/de_DE/es_ES/fr_FR/en_US`), 30s `listenFor` / 3s `pauseFor`, shows local badge. Audio messages stay; transcription is additional — can be extended to Vosk/Whisper file mode later

## [1.26.4] - 2026-08-31

- **Todo editor:** reworked "Изменить список" from small dialog to full bottom sheet — header with clock (tap → date/time & repeat sheet) and importance chips (Normal/Important/Urgent) + task list with colored priority dots (tap to cycle), inline subtasks and quick delete; each row shows `↳` for children and `∙` priority color, time can be set/cleared from the top menu
- **Widget:** subtasks now stay together inside one task — parent row shows `↳ sub • sub +N` preview (up to 3 names + counter) under the title, instead of separate rows or hidden "+N"

## [1.26.3] - 2026-08-31

- **Widget:** removed `+` quick-add button (use long-press app icon → Quick note); tasks now grouped by priority (Urgent / Important / Normal) with overdue on top, instead of time buckets
- **Widget:** sorting is now priority-first (Urgent above Important above Normal, overdue first within each group, then by nearest deadline)

## [1.26.2] - 2026-08-28

- **Folders:** Smart folder now as submenu under New folder (tap → sheet with smart toggles), cache moved
- **Settings:** Cache & Trash moved to bottom (below Security, above About)
- **Widget:** header attached to window (no floating gap, larger hitboxes), corners fixed (no inset gap on sides)

## [1.26.1] - 2026-08-28

- **Widget:** one task per entry (subtasks aggregated as "+N"), parent cannot be checked until subtasks done
- **Widget header:** attached to window (no floating gap), larger +/gear hitboxes (32dp) for reliable taps
- **Shortcuts:** long-press app icon now shows Quick note and Upcoming tasks (dynamic ShortcutManager)
- **Updater:** picks APK matching installed variant (arm64 vs universal) — no more downgrade on auto-update
- **Composer:** single outline, full-width `lg` radius — no double blue corners
- **Potato PC:** `tool/potato_retry.dart` with 3× retry and culprit reporting

## [1.26.0] - 2026-08-28

- **Cache:** RSS and trash/media merged into one "Cache & Trash" card with auto-clean info (trash + temp cleared every 48h) and live size
- **Widget:** header attached to window (no floating pill) with larger +/gear hitboxes; one task per entry (subtasks aggregated as "+N"); parent cannot be completed until subtasks done; resize smooth (targetCell 3×3, updatePeriod 0); always sort by time (newest first), period filter fixed ("Today" shows only today)
- **Voice:** waveform is now the scrub bar — drag the waves to seek, thumb follows progress (old recordings show synthetic waves)
- **Chat composer:** single outline (no double blue corners), full-width with larger radius
- **App Shortcuts:** long-press app icon → Quick note and Upcoming tasks
- **Updater:** auto-update picks APK matching installed variant (universal vs arm64/x86_64) to avoid downgrade
- **Smart folders:** moved under its own "Smart folders" tab for future extensibility
- **Potato PC:** `tool/potato_retry.dart` — auto-kills hung builds and retries 3×, reports culprit script

## [1.25.0] - 2026-08-28

- **Widget:** priority sorting — tasks sort by importance (Urgent/Important/Normal) then by time; new sort switch in widget settings (priority vs time)
- **Chat composer:** input field stretched to full width with larger corners, better use of horizontal space
- **Voice:** redesigned recording panel (Telegram-style with lock/cancel hints) and scrubbing — drag the waveform to seek, thumb follows progress
- **Smart folders:** auto folders "Tasks" and "Notes" (all chats by type) — toggle in Settings → Folders
- **Drafts:** chat list now shows "Draft: ..." instead of last message when you have unsent text
- **Widget hot add:** `+` next to gear — quick task — pick a Tasks chat and the todo editor opens immediately
- **Tasks long-press:** draft text you already typed is now prefilled as the first todo item
- **Bug fixes:** widget/agenda tap now opens the chat for editing (text tap → chat, checkbox → toggle); lock screen no longer shows ghost pattern after disable; fresh install no longer restores old Google backup (allowBackup disabled); Settings shows cache weight (media/trash/temp) and one-tap trash clear

## [1.24.0] - 2026-08-28

- **Flatter, cleaner UI:** removed card shadows and soft-faded tints, tightened section spacing and empty states, reduced input-field rounding — a more compact, Telegram-style look
- **Android widget:** the task list now scrolls, so it can show many more tasks (20-row limit lifted — every undone task is reachable)

## [1.23.2] - 2026-08-28

- Rebaked the 1.23.1 release with the official signing key so existing installs update cleanly (previous build used a different key)

## [1.23.1] - 2026-08-28

- Fix: updating from beta `1.23.0-beta.*` to stable `1.23.0` inside the app now works (version compare treated `1.23.0-beta` == `1.23.0` — fixed to treat stable as newer)
- Fix: dynamic color toggle removed (was non-functional)
- Fix: composer input field radius `pill → lg` (less rounded)
- Fix: backup screen redesign — sliders now `SliderTheme thumb9/track4/overlay20/valueIndicator always` with pill badges & icons, cards `TNRadii.md + shadow`, sections unified
- Fix: missing translations added (`overdue/deselect/filter_week` for 6 languages) — agenda filters & selection bar now fully localized

## [1.23.0] - 2026-08-28

- **Search 2.0:** highlighted query (accent pill), empty state with illustration + clear CTA, chip focus rings
- **Swipe actions:** chats dismissible — swipe right → pin, left → archive with Snackbar undo + haptics; selection bar now has select-all toggle
- **Composer:** hashtag autocomplete (type # + overlay of top 8 tags), tonal bar with divider
- **Android:** portrait lock removed (landscape/tablet ready), edge-to-edge behind system bars (Android 15), WindowInsets handling
- **Agenda:** filter chips (All/Overdue/Today/Week/High), priority dots, empty state illustration, pulls from unified card spec
- **Batch:** select-all in chat list, batch export ready
- **Backup redesign:** sliders fixed — `SliderTheme` with `thumb 9 / track 4 / overlay 20`, value indicator always, pill value badges with icons, card `TNRadii.md + border + shadow`; section `4/20/4/8` unified

## [1.22.0] - 2026-08-28

- **Design ecosystem:** unified UI tokens — one radius/spacing/typography scale, single card/surface spec, consistent bubbles/composer/search across every screen (promoted from beta)
- Light & dark palettes refreshed: better contrast for secondary text, subtle card shadows on light theme, softer chat background
- List: new empty states with illustration + CTA, pill-shaped folder chips with ink, archive header as card, extended FAB with label, improved selection bar
- Chats: all bubbles share one decoration + shadow, condensed due pill with warning icon when overdue, pinned badge on accent, composer as tonal bar with dividers
- Widgets & secondary screens (Agenda/Trash/Settings) now use the same card + section spec as the main list
- Theme: Material 3 AppBar/Card/Chip/Input themes wired, predictive-back transitions on Android
- Task chats: **tap** send → schedule sheet (due time + priority), **long-press** send → todo group editor (parent + subtasks at once)

## [1.21.1] - 2026-08-27

- Task chats: pressing the send button now opens the schedule sheet, where you can pick the task priority (Normal / Important / Urgent) right below the time presets — so every task typed in the chat gets its importance

## [1.21.0] - 2026-08-27

- Task importance: each task now has a priority profile (Normal / Important / Urgent) — pick it when creating or editing a task, a small colored dot marks it in the chat
- Home-screen widget now groups tasks into Overdue / Today / Tomorrow / Later sections
- Home-screen widget task rows get a subtle colored frame matching their importance
- Welcome screen now asks for microphone permission so voice notes work right away

## [1.20.3] - 2026-08-27

- Fix: existing pattern/PIN lock settings now migrate correctly after update (no more lockout)
- Fix: Windows snooze from toast notifications now works
- Fix: memory leak from gesture recognizers in message links
- Fix: audio progress bar no longer shows wrong duration when switching tracks
- Fix: task completion sound now uses notification volume (not media)
- Fix: biometric failure in lock settings now falls back to code prompt

- Fix: pinned messages no longer move to the top — they stay in their original position with a pin icon

## [1.20.1] - 2026-08-26

- Fix: setting a PIN code no longer breaks the pattern lock — secrets are now stored per method
- Removing a code method now properly clears its stored secret
- "Pin" action is now available in the selection mode menu (long-press a message → menu → Pin) for mobile users

## [1.20.0] - 2026-08-26

- Pin messages: long-press or right-click a message to pin it; pinned messages float to the top of the chat with a banner that shows the count, tap to jump to any pinned message or unpin it from the list
- Pin icon now appears on pinned message bubbles so they're easy to spot
- Drafts: unsent text is now saved automatically per chat and restored when you return; drafts clear on send
- Enter key now inserts a newline instead of sending the message (Telegram-style)
- Long-press send with date picker now only works in task chats (was also triggering in notes)
- Settings lock subtitle correctly shows "Multiple methods" when more than one method is enabled

## [1.19.0] - 2026-08-26

- Multi-lock: you can now enable several unlock methods at once (biometrics + pattern + PIN); the lock screen shows all active methods with a switcher, and settings use checkboxes so each method is configured independently
- Backward-compatible: existing single-method lock settings migrate automatically

## [1.18.1] - 2026-08-26

- Fix: "What's new" changelog dialog was invisible when app lock was enabled — it now appears after the lock gate opens for the first time

## [1.18.0] - 2026-08-26

- Samsung biometrics fix: combined prompt (biometric + device credential) is now tried first; the previous two-step cascade broke on OneUI; added a short delay before auto-prompt and cancel-on-dispose so the sheet never lingers
- "What's New" dialog is no longer blocked by the lock screen — it appears above the lock gate so users see the changelog immediately after an update
- Widget text tap now opens the relevant chat; only the checkbox toggles the task (previously the entire row was a toggle)
- Long-press send now works in note chats too — creates a timed text entry that fires a notification at the chosen date/time but does NOT appear in the widget (tasks only)
- Time presets in the schedule sheet: 07:00 / 09:00 / 12:00 / 13:00 / 15:00 / 17:00 / 19:00 / 21:00
- Widget folder chips now scroll horizontally with a mouse on Windows
- "New folder" chip removed from the list screen tab bar (it stays in Settings)

## [1.17.0] - 2026-08-26

- Widget period rework: "All tasks" removed, "Week" replaced by "Upcoming" (overdue + today + tomorrow + day after tomorrow); legacy saved values migrate automatically
- The widget now follows the IN-APP language instead of the system one (fixed English widget after changing the app language)
- Trash screen: retention buttons replaced with a slider in the shared style (1 / 7 / 30 days / forever)
- RSS cache-size slider restyled to match the other sliders
- "New folder" in Settings now opens the name + color dialog (color was impossible to pick from there)
- Time picker switched to numeric input mode — the round dial mis-taps on Samsung skins; bottom sheets respect the gesture-nav bar
- About screen: version constant is now covered by a test against pubspec (it had silently stuck at 1.16.2 for three releases — fixed)

## [1.16.5] - 2026-08-26

- Fixed inverted chat order — new messages appear at the BOTTOM again, old ones stack upward (a builder-index regression from the lazy-list change)
- The scroll controller is now actually attached, so opening a chat and sending pins the view to the newest message
- Removed the yellow underlines on the lock screen (it was drawn without a Material ancestor, so Flutter painted its debug fallback text style)

## [1.16.4] - 2026-08-26

- One permanent release signing key generated and wired everywhere (local builds via android/key.properties, CI via updated secrets) — daily reinstalls caused by mismatched debug/local signatures are over
- NOTE: updating from ≤ 1.16.3 requires ONE final uninstall + fresh install because the signing identity changes this single time; every later update installs cleanly on top

## [1.16.3] - 2026-08-26

- Lock entry in Settings renamed to "Lock" with a padlock icon; the on/off switch inside is now labeled "Lock" too (method selection unchanged below it)
- Redesigned lock screen: gradient background, app logo with accent glow, frosted input card
- Chats: auto-scroll to the bottom when opening a chat and after sending, so new messages always appear from the bottom edge
- About screen now actually shows the app icon (asset was missing from the bundle)

## [1.16.2] - 2026-08-26

- App lock: cascaded verification — biometrics first, then device PIN/pattern fallback; a failed fingerprint can no longer make the lock impossible to remove
- New "About" section at the bottom of Settings: version, tagline, in-app changelog, manual "Check for updates" and ko-fi link

## [1.16.1] - 2026-08-26

- Fixed garbled Russian/Ukrainian (and some German/Spanish/French) interface strings introduced in recent releases — all translations verified against a new audit script and regression tests
- Redesigned "Deleted · Undo" as an in-app pill with a circular 5-second countdown ring — it no longer lingers on screen indefinitely

## [1.16.0] - 2026-08-26

- App lock reworked into its own sub-screen with three methods: biometrics, in-app pattern and in-app PIN code
- Re-lock timing setting: keep the app unlocked immediately / 5 minutes / 10 minutes after unlocking
- Fixed a long-standing bug: daily tasks now reset exactly at midnight, not at their execution time — checked off yesterday means a fresh instance this morning in the widget too
- Completing an overdue daily task on the next day now hands over to the CURRENT day at midnight instead of skipping it

## [1.15.2] - 2026-08-26

- Fixed: "package corrupted" during in-app updates — local builds are now signed with the same key as published releases (one signature everywhere)
- Hardened installer: APK integrity verified before install, clear error messages instead of silent resets, reinstall hint on signing-key mismatch

## [1.15.1] - 2026-08-26

- Fixed: the "What's new" dialog now gets its text from this file — CI releases have proper notes again
- More reliable APK updates: only .apk assets are considered for download

## [1.15.0] - 2026-08-26

- Password-encrypted backups (AES-256-GCM): local copies, Google Drive and Nextcloud
- Biometric app lock: fingerprint / face / device PIN on start and resume
- Undo for deleted entries — an "Undo" snackbar instead of confirmation dialogs
- Snooze reminders (+10 min / +1 hour) right from the notification
- Tag manager and an agenda screen for upcoming tasks
- Pinned entries at the top of chats; "#tag" search; Markdown chat export

## [1.14.0] - 2026-08-26

- Redesigned tasks widget: header with a counter, card-style rows, red overdue dot
- Widget check-off sound now plays on the notification stream (no longer interrupts music)
- Windows: reminders arrive as own Telegram-style toast with snooze buttons
- Forwarding no longer drops recurrence rules; media files are copied on forward
- Cloud restore merges data by updatedAt instead of wiping the device
- Faster chats, SHA-256 verified APK updates, PKCE for Google Drive
