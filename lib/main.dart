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
import 'src/dialogs.dart';
import 'src/media.dart';
import 'src/models.dart';
import 'src/reminder_engine.dart';
import 'src/reminders.dart';
import 'src/share_in.dart';
import 'src/sync.dart';
import 'src/theme.dart';
import 'src/widget_bridge.dart';
import 'src/widgets.dart';
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
  Timer? _pendingHotAddTimer;
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
    WidgetBridge.onHotAdd = () {
      final m = _loadedModel;
      if (m == null) return;
      _handleHotAdd(m);
    };
    // Cold start: the app was launched by tapping a task text in the widget.
    _pendingOpenChatCheck();
    _pendingHotAddCheck();
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

  Future<void> _pendingHotAddCheck() async {
    if (_isTestEnv) return;
    _pendingHotAddTimer = Timer(const Duration(milliseconds: 900), () async {
      if (!mounted) return;
      final pending = await WidgetBridge.takePendingHotAdd();
      if (!pending || !mounted) return;
      final m = _loadedModel;
      if (m == null) return;
      _handleHotAdd(m);
    });
  }

  Future<void> _handleHotAdd(AppModel model) async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    // Pick a tasks chat
    final tasksChats = model.state.chats.where((c) => c.kind == 'tasks' && !c.isTrashed && !c.archived).toList();
    if (tasksChats.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(model.tr('need_chat'))));
      return;
    }
    String? pickedId;
    if (tasksChats.length == 1) {
      pickedId = tasksChats.first.id;
    } else {
      pickedId = await showDialog<String>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          backgroundColor: model.p.modalBg,
          title: Text(model.tr('hot_add_pick'), style: TextStyle(color: model.p.text, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 300,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: tasksChats.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: model.p.divider),
              itemBuilder: (_, i) {
                final c = tasksChats[i];
                return ListTile(
                  leading: ChatAvatar(chat: c, size: 32, iconSize: 16),
                  title: Text(c.name, style: TextStyle(color: model.p.text)),
                  onTap: () => Navigator.pop(dctx, c.id),
                );
              },
            ),
          ),
        ),
      );
    }
    if (pickedId == null) return;
    final items = await showTodoEditorDialog(ctx, model);
    if (items == null || items.isEmpty) return;
    final entry = Entry(
      id: uid('e'),
      chatId: pickedId,
      type: 'todo',
      ts: DateTime.now().millisecondsSinceEpoch,
      text: '',
      items: items,
    );
    model.state.entries.add(entry);
    await model.save();
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(model.tr('todo_added', [tasksChats.firstWhere((c) => c.id == pickedId).name]))));
  }

  @override
  void dispose() {
    _pendingOpenChatTimer?.cancel();
    _pendingHotAddTimer?.cancel();
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
                    surfaceContainerHighest: p.bgChat,
                    outline: p.divider,
                    outlineVariant: p.divider.withValues(alpha: 0.5),
                  ),
                  scaffoldBackgroundColor: p.bgList,
                  appBarTheme: AppBarTheme(
                    backgroundColor: p.bgList,
                    foregroundColor: p.text,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    surfaceTintColor: Colors.transparent,
                    centerTitle: false,
                    titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
                    iconTheme: IconThemeData(color: p.textSoft),
                  ),
                  cardTheme: CardThemeData(
                    color: p.bgChat,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TNRadii.md),
                      side: BorderSide(color: p.divider.withValues(alpha: 0.45)),
                    ),
                    margin: EdgeInsets.zero,
                  ),
                  chipTheme: ChipThemeData(
                    backgroundColor: p.bgChat,
                    selectedColor: p.accent,
                    disabledColor: p.bgChat,
                    labelStyle: TextStyle(fontSize: 13, color: p.textSoft),
                    secondaryLabelStyle: const TextStyle(fontSize: 13, color: Colors.white),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TNRadii.pill)),
                    side: BorderSide(color: p.divider.withValues(alpha: 0.6)),
                  ),
                  inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: p.bgChat,
                    hintStyle: TextStyle(color: p.textFaint, fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TNRadii.md),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TNRadii.md),
                      borderSide: BorderSide(color: p.accent, width: 1.4),
                    ),
                  ),
                  pageTransitionsTheme: const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
                      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    },
                  ),
                  snackBarTheme: SnackBarThemeData(
                    backgroundColor: p.bgChat,
                    contentTextStyle: TextStyle(color: p.text),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TNRadii.md)),
                    behavior: SnackBarBehavior.floating,
                  ),
                  dialogTheme: DialogThemeData(
                    backgroundColor: p.modalBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TNRadii.lg)),
                  ),
                  bottomSheetTheme: BottomSheetThemeData(
                    backgroundColor: p.modalBg,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(TNRadii.sheet))),
                  ),
                  dividerTheme: DividerThemeData(color: p.divider.withValues(alpha: 0.6), thickness: 1),
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
