# Changelog

All notable TN releases. The newest section is shown to users inside the
app ("What's new" dialog) — keep entries user-facing and concise.
Everything published here goes to GitHub in English only.

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
