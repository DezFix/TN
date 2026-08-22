import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../src/app_model.dart';
import '../src/i18n.dart';
import '../src/theme.dart';
import 'list_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.model});
  final AppModel model;
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String _lang = 'ru';
  String _theme = 'system';

  @override
  void initState() {
    super.initState();
    _lang = widget.model.state.lang;
    _theme = widget.model.state.theme;
    if (_theme != 'light' && _theme != 'dark' && _theme != 'system') _theme = 'system';
  }

  Future<void> _finish() async {
    await widget.model.setLang(_lang);
    await widget.model.setTheme(_theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tn-welcome-done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ListScreen(model: widget.model)));
  }

  @override
  Widget build(BuildContext context) {
    final tr = makeTranslator(_lang);
    final effective = _theme == 'dark'
        ? 'dark'
        : _theme == 'light'
            ? 'light'
            : (MediaQuery.platformBrightnessOf(context) == Brightness.dark ? 'dark' : 'light');
    final p = paletteFor(effective);

    return Scaffold(
      backgroundColor: p.bgList,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: const Text('TN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
                  ),
                  const SizedBox(width: 12),
                  Text('TN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: p.text, letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: 16),
              Text(tr('welcome_headline'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text, height: 1.2)),
              const SizedBox(height: 10),
              Text(tr('welcome_desc'), style: TextStyle(fontSize: 15, color: p.textSoft, height: 1.45)),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _feat(tr('welcome_feat1'), p),
                    const SizedBox(height: 8),
                    _feat(tr('welcome_feat2'), p),
                    const SizedBox(height: 8),
                    _feat(tr('welcome_feat3'), p),
                    const SizedBox(height: 8),
                    _feat(tr('welcome_feat4'), p),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(tr('welcome_lang'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (code, label) in appLanguages)
                    ChoiceChip(
                      label: Text(label),
                      selected: _lang == code,
                      onSelected: (_) => setState(() => _lang = code),
                      selectedColor: p.accent,
                      backgroundColor: p.bgChat,
                      labelStyle: TextStyle(color: _lang == code ? Colors.white : p.textSoft, fontWeight: FontWeight.w600, fontSize: 13),
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: _lang == code ? p.accent : p.divider)),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(tr('welcome_theme'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in ['light', 'dark', 'system'])
                    ChoiceChip(
                      label: Text(t == 'system' ? 'System' : tr(t)),
                      selected: _theme == t,
                      onSelected: (_) => setState(() => _theme = t),
                      selectedColor: p.accent,
                      backgroundColor: p.bgChat,
                      labelStyle: TextStyle(color: _theme == t ? Colors.white : p.textSoft, fontWeight: FontWeight.w600, fontSize: 13),
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: _theme == t ? p.accent : p.divider)),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: p.accent, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: _finish,
                  child: Text(tr('welcome_start'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              Center(child: Text('TN · ${tr('chat_subtitle')}', style: TextStyle(fontSize: 11, color: p.textFaint))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feat(String text, Palette p) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.35))),
        ],
      );
}
