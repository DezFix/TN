import 'dart:async' show unawaited, Timer;
import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_model.dart';
import 'src/backup.dart';
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
  runApp(const TN());
}

class TN extends StatefulWidget {
  const TN({super.key});

  @override
  State<TN> createState() => _TNState();
}

const _appVersion = '8.2';

bool _quitting = false;

/// True under `flutter test` — window/tray channels never answer there.
final bool _isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');

/// Windows: phone-shaped window, close button hides to tray instead of
/// quitting — reminders keep arriving while TN sits in the tray.
Future<void> _initWindowAndTray() async {
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
  final menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(label: 'Открыть TN', onClicked: (_) => windowManager.show()),
    MenuSeparator(),
    MenuItemLabel(label: 'Выход', onClicked: (_) async {
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
  bool _whatsNewChecked = false;
  bool _shareInWired = false;
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetBridge.onOpenSettings = () {
      _navKey.currentState?.pushNamed('/widget-settings');
    };
  }

  @override
  void dispose() {
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
              routes: {
                '/widget-settings': (_) => WidgetSettingsScreen(model: model),
              },
              home: Builder(
                builder: (innerCtx) {
                  if (_showWelcome) {
                    return WelcomeScreen(model: model);
                  }
                  if (!_whatsNewChecked) {
                    _whatsNewChecked = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _maybeShowWhatsNew(innerCtx, model);
                    });
                  }
                  if (!_shareInWired) {
                    _shareInWired = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    // Ask for the notifications permission right away; the exact-alarms
    // system page is only opened from the welcome flow / reminder creation.
    await RemindersService.instance.requestNotificationsPermission();
    try {
      final prefs = await SharedPreferences.getInstance();
      _showWelcome = !(prefs.getBool('tn-welcome-done') ?? false);
    } catch (_) {}
    if (Platform.isWindows && !_isTestEnv) {
      // Fire-and-forget: window/tray setup must never block app boot.
      unawaited(_initWindowAndTray());
      // Telegram-style delivery: in-app banner / toast, no native scheduling.
      ReminderEngine.instance.start(model, _navKey);
    }
    if (!_isTestEnv) {
      unawaited(_initSync(model));
      // Scheduled local backups (daily/weekly into the chosen folder).
      unawaited(BackupService.maybeAutoBackup(model.state));
      Timer.periodic(
          const Duration(hours: 1),
          (_) => unawaited(BackupService.maybeAutoBackup(model.state)));
    }
    return model;
  }

  /// Google Drive sync: restore newer cloud state on boot, then push local
  /// changes (debounced) so phone and PC stay in step.
  Future<void> _initSync(AppModel model) async {
    await SyncService.instance.bind(model);
    model.addListener(SyncService.instance.notifyChanged);
    await SyncService.instance.syncOnStart();
  }

  Future<void> _maybeShowWhatsNew(BuildContext context, AppModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Preferred source: the latest GitHub release notes.
      try {
        final r = await http
            .get(
              Uri.parse('https://api.github.com/repos/DezFix/TN/releases/latest'),
              headers: {
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'TN-app',
              },
            )
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final tag = j['tag_name'] as String?;
          final name = (j['name'] as String?) ?? '';
          final body = (j['body'] as String?) ?? '';
          final seenTag = prefs.getString('tn-seen-release');
          if (tag != null &&
              tag.isNotEmpty &&
              tag != seenTag &&
              body.trim().isNotEmpty &&
              context.mounted) {
            await _showReleaseDialog(context, model,
                title: name.isNotEmpty ? name : 'TN $tag', markdown: body);
            await prefs.setString('tn-seen-release', tag);
            await prefs.setString('tn-last-version', _appVersion);
            return;
          }
        }
      } catch (_) {}

      // Offline fallback: bundled notes.
      final seen = prefs.getString('tn-last-version');
      if (seen == _appVersion) return;
      if (!context.mounted) return;
      final p = model.p;
      final fix = model.tr('whatsnew_fix');
      final upd = model.tr('whatsnew_update');
      final hasSplit = fix != 'whatsnew_fix' && upd != 'whatsnew_update';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: p.modalBg,
          title: Text('TN $_appVersion',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          content: SingleChildScrollView(
            child: hasSplit
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Fix', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accent, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(fix, style: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5)),
                      const SizedBox(height: 12),
                      Text('Update', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accent, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(upd, style: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5)),
                    ],
                  )
                : Text(model.tr('whatsnew_body'),
                    style: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5)),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: 'https://ko-fi.com/k_k'));
                var opened = false;
                try {
                  opened = await launchUrl(Uri.parse('https://ko-fi.com/k_k'),
                      mode: LaunchMode.externalApplication);
                } catch (_) {}
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(opened
                        ? model.tr('support')
                        : 'ko-fi.com/k_k • ${model.tr('support')}'),
                  ));
                }
              },
              child: Text('❤ ko-fi', style: TextStyle(color: p.accent)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.accent),
              onPressed: () => Navigator.pop(ctx),
              child: Text(model.tr('close')),
            ),
          ],
        ),
      );
      await prefs.setString('tn-last-version', _appVersion);
    } catch (_) {}
  }

  Future<void> _showReleaseDialog(
    BuildContext context,
    AppModel model, {
    required String title,
    required String markdown,
  }) async {
    final p = model.p;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.modalBg,
        title: Text(title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: markdown,
              selectable: false,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5),
                h1: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
                h2: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                h3: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.accent),
                listBullet: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5),
                code: TextStyle(fontSize: 12, color: p.textSoft, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: 'https://ko-fi.com/k_k'));
              var opened = false;
              try {
                opened = await launchUrl(Uri.parse('https://ko-fi.com/k_k'),
                    mode: LaunchMode.externalApplication);
              } catch (_) {}
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(opened
                      ? model.tr('support')
                      : 'ko-fi.com/k_k • ${model.tr('support')}'),
                ));
              }
            },
            child: Text('❤ ko-fi', style: TextStyle(color: p.accent)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.accent),
            onPressed: () => Navigator.pop(ctx),
            child: Text(model.tr('close')),
          ),
        ],
      ),
    );
  }
}