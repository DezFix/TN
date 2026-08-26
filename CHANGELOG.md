# Changelog

All notable TN releases. The newest section is shown to users inside the
app ("What's new" dialog) — keep entries user-facing and concise.
Everything published here goes to GitHub in English only.

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
