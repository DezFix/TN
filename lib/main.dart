import 'package:flutter/material.dart';

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

class _TNState extends State<TN> {
  late final Future<AppModel> _future = _load();

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
              home: ListScreen(model: model),
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
    return model;
  }
}