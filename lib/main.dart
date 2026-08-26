import 'dart:async' show unawaited, Timer;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_lock.dart';
import 'src/app_model.dart';
import 'src/app_update.dart';
import 'src/backup.dart';
import 'src/media.dart';
import 'src/reminder_engine.dart';
import 'src/reminders.dart';
import 'src/share_in.dart';
import 'src/sync.dart';
import 'src/theme.dart';
import 'src/widget_bridge.dart';
import 'screens/chat_screen.dart';
import 'screens/list_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/widget_settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Hardware-backed AES/PBKDF2 where available (Android Keystore etc.);
  // silently falls back to pure Dart otherwise.
  try {
    FlutterCryptography.enable();
  } catch (_) {}
  runApp(const TN());
}

class TN extends StatefulWidget {
  const TN({super.key});

  @override
  State<TN> createState() => _TNState();
}

bool _quitting = false;

/// True under `flutter test` — window/tray channels never answer there.
final bool _isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');

/// Windows: phone-shaped window, close button hides to tray instead of
/// quitting — reminders keep arriving while TN sits in the tray.
Future<void> _initWindowAndTray(AppModel model) async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(412, 892),
    minimumSize: Size(320, 560),
    title: 'TN',
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    windowManager.addListener(_TrayWindowListener());
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });

  final tray = SystemTray();
  await tray.initSystemTray(title: 'TN', iconPath: 'assets/app_icon.ico', toolTip: 'TN');
  // Localized labels (the model is fully loaded by the time we get here).
  final menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(label: model.tr('tray_open'), onClicked: (_) => windowManager.show()),
    MenuSeparator(),
    MenuItemLabel(label: model.tr('tray_quit'), onClicked: (_) async {
      _quitting = true;
      await tray.destroy();
      await windowManager.destroy();
    }),
  ]);
  await tray.setContextMenu(menu);
  tray.registerSystemTrayEventHandler((eventName) {
    if (eventName == kSystemTrayEventClick) {
      windowManager.isVisible().then((v) => v ? windowManager.hide() : windowManager.show());
    } else if (eventName == kSystemTrayEventRightClick) {
      tray.popUpContextMenu();
    }
  });
}

class _TrayWindowListener extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    // The X button hides to the tray; real exit only via tray menu.
    if (_quitting) return;
    await windowManager.hide();
  }
}

class _TNState extends State<TN> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late final Future<AppModel> _future = _load();
  bool _shareInWired = false;
  bool _showWelcome = false;
  AppModel? _loadedModel;
  Timer? _pendingOpenChatTimer;
  bool _whatsNewShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetBridge.onOpenSettings = () {
      _navKey.currentState?.pushNamed('/widget-settings');
    };
    WidgetBridge.onOpenChat = (chatId) {
      final m = _loadedModel;
      if (m == null) return;
      _navKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ChatScreen(model: m, chatId: chatId),
      ));
    };
    // Cold start: the app was launched by tapping a task text in the widget.
    _pendingOpenChatCheck();
  }

  Future<void> _pendingOpenChatCheck() async {
    _pendingOpenChatTimer = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      final chatId = await WidgetBridge.takePendingOpenChat();
      if (chatId == null || !mounted) return;
      final m = _loadedModel;
      if (m == null) return;
      _navKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ChatScreen(model: m, chatId: chatId),
      ));
    });
  }

  @override
  void dispose() {
    _pendingOpenChatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tasks checked from the home-screen widget land in storage while the
    // app is backgrounded — pull them in when we come back.
    if (state == AppLifecycleState.resumed) {
      _future.then((m) => m.syncIfExternal());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppModel>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return MaterialApp(
            home: const Scaffold(body: SizedBox()),
            debugShowCheckedModeBanner: false,
          );
        }
        final model = snap.data!;
        _loadedModel ??= model;
        return ListenableBuilder(
          listenable: model,
          builder: (context, _) {
            // 'system' theme was removed — only explicit light/dark remain.
            final themeName = model.state.theme;
            final pl = paletteFor('light');
            final pd = paletteFor('dark');
            ThemeData buildTheme(Palette p, Brightness b) => ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme(
                    brightness: b,
                    primary: p.accent,
                    onPrimary: Colors.white,
                    secondary: p.accentDk,
                    onSecondary: Colors.white,
                    error: p.danger,
                    onError: Colors.white,
                    surface: p.bgList,
                    onSurface: p.text,
                  ),
                  scaffoldBackgroundColor: p.bgList,
                  pageTransitionsTheme: PageTransitionsTheme(
                    builders: {
                      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    },
                  ),
                  snackBarTheme: SnackBarThemeData(
                    backgroundColor: p.bgChat,
                    contentTextStyle: TextStyle(color: p.text),
                  ),
                  dialogTheme: DialogThemeData(backgroundColor: p.modalBg),
                  bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.modalBg),
                );
            return MaterialApp(
              title: 'TN',
              debugShowCheckedModeBanner: false,
              navigatorKey: _navKey,
              locale: Locale(model.state.lang),
              supportedLocales: const [Locale('ru'), Locale('en'), Locale('uk'), Locale('de'), Locale('es'), Locale('fr')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              themeMode: themeName == 'dark' ? ThemeMode.dark : ThemeMode.light,
              theme: buildTheme(pl, Brightness.light),
              darkTheme: buildTheme(pd, Brightness.dark),
              builder: (context, child) {
                return LockGate(
                  tr: model.tr,
                  onFirstUnlock: _whatsNewShown
                      ? null
                      : () {
                          if (_whatsNewShown || !mounted) return;
                          _whatsNewShown = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            maybeShowWhatsNew(
                                _navKey.currentContext!, model);
                          });
                        },
                  child: child ?? const SizedBox.shrink(),
                );
              },
              routes: {
                '/widget-settings': (_) => WidgetSettingsScreen(model: model),
              },
              home: Builder(
                builder: (innerCtx) {
                  if (_showWelcome) {
                    return WelcomeScreen(model: model);
                  }
                  if (!_shareInWired) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _shareInWired = true;
                      ShareIn.init(model,
                          getContext: () => _navKey.currentContext!,
                          openChat: (chatId, entryId) {
                            _navKey.currentState?.push(MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                  model: model,
                                  chatId: chatId,
                                  scrollToEntryId: entryId,
                                  highlightEntryId: entryId),
                            ));
                          });
                    });
                  }
                  return ListScreen(model: model);
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<AppModel> _load() async {
    final model = AppModel();
    await model.load();
    await RemindersService.instance.init();
    await RemindersService.instance.requestNotificationsPermission();
    _purgeExpiredTrash(model);
    unawaited(MediaStore().purgeTrash());
    try {
      final prefs = await SharedPreferences.getInstance();
      _showWelcome = !(prefs.getBool('tn-welcome-done') ?? false);
    } catch (_) {}
    if (Platform.isWindows && !_isTestEnv) {
      unawaited(_initWindowAndTray(model));
      ReminderEngine.instance.start(model, _navKey);
    }
    if (!_isTestEnv) {
      unawaited(_initSync(model));
      unawaited(BackupService.maybeAutoBackup(model.state));
      Timer.periodic(
          const Duration(hours: 1),
          (_) => unawaited(BackupService.maybeAutoBackup(model.state)));
    }
    return model;
  }

  Future<void> _purgeExpiredTrash(AppModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final retentionDays = prefs.getInt('tn-trash-retention-days') ?? 7;
      if (retentionDays == 0) return; // forever
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - retentionDays * 86400000;
      final expired = model.state.chats.where((c) => c.isTrashed && (c.deletedAt ?? 0) < cutoff).toList();
      if (expired.isEmpty) return;
      for (final chat in expired) {
        for (final e in model.state.entriesFor(chat.id)) {
          try { await MediaStore().remove(e.media); } catch (_) {}
        }
        for (final r in model.state.reminders.toList()) {
          if (r.chatId == chat.id) model.state.reminders.remove(r);
        }
        model.state.entries.removeWhere((e) => e.chatId == chat.id);
      }
      model.state.chats.removeWhere((c) => expired.any((e) => e.id == c.id));
      await model.save();
    } catch (_) {}
  }

  /// Google Drive: bind for OAuth tokens only — upload is manual via Backup screen.
  Future<void> _initSync(AppModel model) async {
    await SyncService.instance.bind(model);
  }
}
