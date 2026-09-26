# TN — notes that feel like a Telegram chat

[![Sponsor](https://img.shields.io/badge/Sponsor%20me-ko--fi-ff5e5b?logo=kofi&logoColor=white)](https://ko-fi.com/k_k)

TN is a conversation with yourself: topic chats instead of folders, messages instead of files. Ideas, to-do lists, photos, voice notes — sorted by topic, with reminders and `#tags`. Notes and media are stored locally. The app checks GitHub for updates, can fetch RSS and link previews, and sends anonymous crash reports to Bugsink unless crash reporting is disabled. [Support the project — ko-fi.com/k_k](https://ko-fi.com/k_k)

> Screenshots below are in English (the interface language is switchable in Settings). Some older screenshots do not yet show every beta feature, including Kanban.

## Chats

Everything starts with the chat list. A fresh install greets you with an empty screen and a hint — tap the big button or the ✎ button at the bottom right.

<img src="doc/screen/02_chats_empty.png" width="270" alt="Empty chat list">

A lived-in list looks like a messenger: avatar with icon, name, last message and time. On top — search plus filters: All, Tasks, Notes, Tags, Upcoming.

<img src="doc/screen/08_chat_list.png" width="270" alt="Chat list with filters">

### New chat

Creating a chat picks its name, type, icon and color. Types:

- **Notes** — plain notes: text, photos, voice, files;
- **Tasks** — tasks with checkboxes, deadlines and repeats;
- **RSS channel** — read-only feed, new posts arrive as messages;
- **Kanban** — board with columns (in beta for now, see below).

<img src="doc/screen/03_new_chat.png" width="270" alt="Creating a chat">

## Notes

A notes chat is a plain conversation with yourself. Hashtags in the text are highlighted and collected into pills under the message; search and the tags screen run on them.

<img src="doc/screen/04_chat_notes.png" width="270" alt="Notes chat with a hashtag">

A long press on a message enables selection mode: tick several entries at once.

<img src="doc/screen/05_selected.png" width="270" alt="Selecting messages">

The ⋮ menu offers: edit, pin, copy, forward, share to an external app, delete.

<img src="doc/screen/06_selection_menu.png" width="270" alt="Message actions menu">

Deleted entries can always be brought back: instead of a confirmation dialog, a “Deleted · Undo” pill with a ~5-second countdown ring appears at the bottom.

<img src="doc/screen/07_undo.png" width="270" alt="Undo delete">

## Tasks and reminders

In a tasks chat the send button opens the **“Date, time & repeat”** sheet: date, time (07:00–21:00 presets), repeat (once / every day / weekdays / pick days / monthly) and priority (Normal / Important / Urgent).

<img src="doc/screen/09_schedule.png" width="270" alt="Date, time, repeat and priority">

A finished task lives in the chat as a card with a checkbox and a due pill. Overdue items are highlighted.

<img src="doc/screen/10_chat_tasks.png" width="270" alt="Tasks chat with a deadline">

Reminders arrive as notifications with **Postpone** (+24 hours) and **Done** (close the task right from the shade) buttons. Done tasks never ring: checking one cancels its alarm automatically.

Long-pressing send opens the list editor: several items and sub-items at once, with the due date set via the clock icon in the same sheet.

## Search and tags

Search looks across all chats and entries (text, tags, checklist items). Tapping a result opens the chat scrolled exactly to the found message, highlighted.

<img src="doc/screen/11_search.png" width="270" alt="Searching chats and notes">

## Kanban board (beta)

A new chat type for running work in columns. Three by default — Idea / In progress / Done; custom columns are managed via ⋮ → Columns (or by long-pressing a tab): rename, add, delete. Deleting a column moves its cards into the first remaining one.

- Tabs with counters above the messages switch columns;
- swiping a card right pushes it to the next column (the last one is a stop);
- the large “…” button on a card opens a move sheet with every column, including backwards moves;
- deleting a card or column uses the same auto-dismissing “Deleted · Undo” banner as the rest of the app;
- tap send = a quick text card in the current column; long-press send opens a checklist editor with optional deadline, repeat and priority;
- moving a todo card into the last column checks every item (alarms stop); moving it back out unchecks them; Undo restores the exact checkmarks and deadline;
- kanban tasks show up in the agenda; forwarding into kanban lands the card in the first column.

## Widgets

Two widgets can be placed on the home screen:

- **Tasks** — undone todos from all chats (“Today” / “Upcoming” modes, priority-first with overdue items highlighted). Checkboxes tick right on the widget and sync with the app; tapping the text opens the chat at that message;
- **Kanban** — all card types from one selected board, grouped into at most three deduplicated columns. It shows deadlines (or “No deadline”) and is read-only: there are no checkboxes or completion triggers. A wide widget shows the columns side by side; a narrow one shows one column and switches columns on tap. Tapping a card opens it in the app.

Background transparency, font size and the Kanban board are configured inside the app (Settings → Widget settings).

## Quick actions from the icon

Long-pressing the TN launcher icon shows two shortcuts with distinct icons:

- 📝 **Quick note** — jump straight into writing a new entry;
- 📅 **Open agenda** — the upcoming-tasks screen. Exact icons can vary by launcher.

## Folders, agenda, archive

- **Folders** — custom chat sets with names and colors (+ smart “Tasks”/“Notes” folders; the Tasks folder includes both Tasks chats and Kanban boards);
- **Agenda (Upcoming)** — every task with a deadline, grouped by day: overdue, today, tomorrow, later; filters All / Overdue / Today / Week / High;
- **Archive** — inactive chats leave the main screen;
- **Trash** — deleted chats wait out the retention period (configurable), one-tap restore.

## Settings

<img src="doc/screen/01_settings.png" width="270" alt="Settings: theme and language"> <img src="doc/screen/12_settings_mid.png" width="270" alt="Settings: folders, widget, lock, cache">

- theme (light/dark), 6 interface languages;
- backups & cloud, trash;
- folders, smart folders, tags, ordering;
- widget, app lock (biometrics / pattern / PIN, re-lock timeout);
- cache & trash with automatic cleanup on launch.

At the bottom — the About section: version, changelog, manual update check.

<img src="doc/screen/13_settings_about.png" width="270" alt="Settings: About"> <img src="doc/screen/14_about.png" width="270" alt="About screen">

## Backups

One zip contains the app database, media and supported widget settings: locally into a folder of your choice (scheduled or manual), to Google Drive or Nextcloud. When a password is set, local and cloud copies use AES-256-GCM encryption; without a password they remain ordinary ZIP files. Restoring takes a couple of taps, including from the welcome screen.

## For developers

Use Flutter 3.41.4, Java 17 and Android NDK 29 for the Android toolchain.

```sh
flutter pub get
flutter run          # run
flutter test         # tests
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --release   # APK: build/app/outputs/flutter-apk/app-release.apk
flutter clean               # remove generated build/cache files
```

Release signing is read from `android/key.properties` or the `TN_*` CI environment variables. Beta builds ship via `vX.Y.Z-beta.N` tags through GitHub Actions (`.github/workflows/build.yml`): Android APKs (universal/arm64/x86_64) + Windows zip, the release is marked as prerelease. The English changelog in `CHANGELOG.md` feeds the in-app “What’s new” dialog and the release body.

## Support

TN is free and ad-free forever, developed on donations: **https://ko-fi.com/k_k** (also GitHub Sponsors).

## License

GPL-3.0 — see [LICENSE](LICENSE).
