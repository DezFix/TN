# TN

[![Sponsor](https://img.shields.io/badge/Sponsor%20me-ko--fi-ff5e5b?logo=kofi&logoColor=white)](https://ko-fi.com/k_k)

Notes that feel like a Telegram chat. [Support the project — ko-fi.com/k_k](https://ko-fi.com/k_k)

TN keeps your notes as a conversation with yourself: topic chats, messages, photos, videos, voice notes, to-do lists, hashtags. Built with Flutter (Dart).

## Features

- Topic chats (e.g. "Ideas", "Work", "Favorites") with icons and colors
- Chat folders: custom names, colors, drag & drop; feed filtering by folder
- Entries as messages: text, photos, videos, voice notes, to-do lists
- To-dos with checkboxes: check items right in the chat; set deadlines and repeats (daily / weekly / monthly) — overdue tasks are highlighted; a virtual "Today" chat collects what's due
- Flexible chats: auto-collect tasks by rules from all chats or a folder into one virtual chat
- Archived chats: keep inactive chats off the main screen (reveal via overscroll at the top)
- Multi-select entries: pin, move, archive, delete a group of messages
- Voice message recording and playback
- `#hashtags` in text
- Search across all chats and entries with jump-to-message and highlighting
- Forward / edit / delete an entry (long press); sharing via the system share sheet
- RSS feeds as chats: new posts arrive as messages
- Home-screen widgets: day/week task lists, check off tasks right from the widget
- One-zip backups: full database + media; restore in a couple of taps, scheduled backups into a folder of your choice
- Light and dark themes
- Interface languages: English, Russian, Ukrainian, German, Spanish, French
- All data stays local on your device

## Run

```
flutter pub get
flutter run
```

## Build APK

```
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`

## Tests

```
flutter test
```

## Support

If TN is useful to you — support the project: **https://ko-fi.com/k_k** (also listed under GitHub Sponsors).

## License

GPL-3.0 — the app is open source, see [LICENSE](LICENSE).
