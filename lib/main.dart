import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app_model.dart';
import 'src/reminders.dart';
import 'screens/list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TN());
}

class TN extends StatefulWidget {
  const TN({super.key});

  @override
  State<TN> createState() => _TNState();
}

const _appVersion = '7.2';

class _TNState extends State<TN> {
  late final Future<AppModel> _future = _load();
  bool _whatsNewChecked = false;

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
            final p = model.p;
            final scheme = ColorScheme(
              brightness: model.state.theme == 'dark' ? Brightness.dark : Brightness.light,
              primary: p.accent,
              onPrimary: Colors.white,
              secondary: p.accentDk,
              onSecondary: Colors.white,
              error: p.danger,
              onError: Colors.white,
              surface: p.bgList,
              onSurface: p.text,
            );
            return MaterialApp(
              title: 'TN',
              debugShowCheckedModeBanner: false,
              themeMode: ThemeMode.light,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: scheme,
                scaffoldBackgroundColor: p.bgList,
                snackBarTheme: SnackBarThemeData(
                  backgroundColor: p.bgChat,
                  contentTextStyle: TextStyle(color: p.text),
                ),
                dialogTheme: DialogThemeData(backgroundColor: p.modalBg),
                bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.modalBg),
              ),
              home: Builder(
                builder: (innerCtx) {
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
    model.startScheduler();
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ko-fi.com/k_k скопировано')));
                }
              },
              child: Text('❤️ ko-fi', style: TextStyle(color: p.accent)),
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