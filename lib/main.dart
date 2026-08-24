import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app_model.dart';
import 'src/reminders.dart';
import 'src/theme.dart';
import 'src/widget_bridge.dart';
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

const _appVersion = '7.5';

class _TNState extends State<TN> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late final Future<AppModel> _future = _load();
  bool _whatsNewChecked = false;
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
    // app is backgrounded вЂ” pull them in when we come back.
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
            // 'system' theme was removed вЂ” only explicit light/dark remain.
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
    return model;
  }

  Future<void> _maybeShowWhatsNew(BuildContext context, AppModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
          title: Text(model.tr('whatsnew_title'),
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
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ko-fi.com/k_k вЂў ${model.tr('support')}')));
                }
              },
              child: Text('вќ¤пёЏ ko-fi', style: TextStyle(color: p.accent)),
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
}