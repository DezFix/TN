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
import 'src/media.dart';
import 'src/reminder_engine.dart';
import 'src/reminders.dart';
import 'src/share_in.dart';
import 'src/sync.dart';
import 'src/theme.dart';
import 'src/updater.dart';
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

const _buildVersion = '1.13.1';

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
    await RemindersService.instance.requestNotificationsPermission();
    _purgeExpiredTrash(model);
    try {
      final prefs = await SharedPreferences.getInstance();
      _showWelcome = !(prefs.getBool('tn-welcome-done') ?? false);
    } catch (_) {}
    if (Platform.isWindows && !_isTestEnv) {
      unawaited(_initWindowAndTray());
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

  /// Numeric compare of "vX.Y.Z" tags against the installed [_buildVersion].
  static bool _isNewerTag(String tag, String current) {
    List<int> parse(String s) => s
        .replaceFirst(RegExp('^v'), '')
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp('[^0-9].*'), '')) ?? 0)
        .toList();
    final a = parse(tag), b = parse(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<void> _maybeShowWhatsNew(BuildContext context, AppModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic>? rel;
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
          rel = jsonDecode(r.body) as Map<String, dynamic>;
        }
      } catch (_) {}

      if (rel == null) return;
      final tag = (rel['tag_name'] as String?) ?? '';
      final name = (rel['name'] as String?) ?? '';
      final body = ((rel['body'] as String?) ?? '').replaceFirst(RegExp(r'^\uFEFF'), '');
      if (tag.isEmpty || body.trim().isEmpty) return;

      final updateAvailable = _isNewerTag(tag, _buildVersion);

      String? apkUrl;
      if (updateAvailable && Platform.isAndroid) {
        final assets = rel['assets'] as List<dynamic>?;
        if (assets != null) {
          String? fallback;
          for (final a in assets) {
            final n = (a as Map<String, dynamic>)['name'] as String? ?? '';
            final u = a['browser_download_url'] as String? ?? '';
            if (n.contains('universal')) fallback = u;
          }
          apkUrl = fallback ?? (assets.isNotEmpty
              ? (assets.last as Map<String, dynamic>)['browser_download_url'] as String?
              : null);
        }
      }

      final pageUrl = (rel['html_url'] as String?) ??
          'https://github.com/DezFix/TN/releases/latest';

      if (prefs.getString('tn-seen-release') != tag && context.mounted) {
        await _showReleaseDialog(context, model,
            title: name.isNotEmpty ? name : 'TN $tag',
            markdown: body,
            updateUrl: updateAvailable ? pageUrl : null,
            apkUrl: apkUrl);
        await prefs.setString('tn-seen-release', tag);
        return;
      }

      if (updateAvailable &&
          prefs.getString('tn-update-prompted') != tag &&
          context.mounted) {
        await _showUpdateDialog(context, model, tag,
            url: pageUrl, apkUrl: apkUrl);
        await prefs.setString('tn-update-prompted', tag);
      }
    } catch (_) {}
  }

  Future<void> _showUpdateDialog(BuildContext context, AppModel model,
      String tag, {required String url, String? apkUrl}) async {
    final p = model.p;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool downloading = false;
        double progress = 0;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: p.modalBg,
            title: Text(model.tr('update_available'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            content: downloading
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: progress > 0 ? progress : null, color: p.accent, backgroundColor: p.divider),
                      const SizedBox(height: 12),
                      Text(model.tr('downloading'), style: TextStyle(fontSize: 13.5, color: p.textSoft)),
                    ],
                  )
                : Text(model.tr('update_hint', [tag]),
                    style: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5)),
            actions: [
              TextButton(
                onPressed: downloading ? null : () => Navigator.pop(ctx),
                child: Text(model.tr('later'), style: TextStyle(color: p.textSoft)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.accent),
                icon: Icon(downloading ? Icons.hourglass_empty : Icons.download, size: 18),
                onPressed: downloading ? null : () async {
                  if (apkUrl != null && Platform.isAndroid) {
                    setDialogState(() { downloading = true; progress = 0; });
                    final result = await Updater.downloadAndInstall(apkUrl, (p) {
                      setDialogState(() => progress = p);
                    });
                    if (result == null && ctx.mounted) {
                      setDialogState(() => downloading = false);
                    }
                  } else {
                    Navigator.pop(ctx);
                    try {
                      await launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  }
                },
                label: Text(model.tr('update_now')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showReleaseDialog(
    BuildContext context,
    AppModel model, {
    required String title,
    required String markdown,
    String? updateUrl,
    String? apkUrl,
  }) async {
    final p = model.p;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool downloading = false;
        double progress = 0;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: p.modalBg,
            title: Text(title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            content: SizedBox(
              width: 340,
              child: downloading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(value: progress > 0 ? progress : null, color: p.accent, backgroundColor: p.divider),
                        const SizedBox(height: 12),
                        Text(model.tr('downloading'), style: TextStyle(fontSize: 13.5, color: p.textSoft)),
                      ],
                    )
                  : SingleChildScrollView(
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
                onPressed: downloading ? null : () async {
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
              if (updateUrl != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  icon: Icon(downloading ? Icons.hourglass_empty : Icons.download, size: 18),
                  onPressed: downloading ? null : () async {
                    if (apkUrl != null && Platform.isAndroid) {
                      setDialogState(() { downloading = true; progress = 0; });
                      final result = await Updater.downloadAndInstall(apkUrl, (p) {
                        setDialogState(() => progress = p);
                      });
                      if (result == null && ctx.mounted) {
                        setDialogState(() => downloading = false);
                      }
                    } else {
                      Navigator.pop(ctx);
                      try {
                        await launchUrl(Uri.parse(updateUrl),
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    }
                  },
                  label: Text(model.tr('update_now')),
                ),
              if (updateUrl == null)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(model.tr('close')),
                ),
            ],
          ),
        );
      },
    );
  }
}
