import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_model.dart';
import '../src/models.dart';
import '../src/theme.dart';
import '../src/widgets.dart';

class ChatEditScreen extends StatefulWidget {
  const ChatEditScreen({super.key, required this.model, this.chat});
  final AppModel model;
  final Chat? chat;
  @override
  State<ChatEditScreen> createState() => _ChatEditScreenState();
}

class _ChatEditScreenState extends State<ChatEditScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.chat?.name ?? '');
  late final TextEditingController _rss = TextEditingController(text: widget.chat?.rssUrl ?? '');
  String? _icon;
  late String _color;
  late String _kind;
  late AutoCollect _ac;

  bool get _editing => widget.chat != null;

  @override
  void initState() {
    super.initState();
    _icon = widget.chat?.icon;
    _color = widget.chat?.color ?? appColors[0];
    _kind = widget.chat?.kind ?? 'note';
    final raw = widget.chat?.autoCollect;
    _ac = raw == null ? AutoCollect() : AutoCollect.fromJson(raw.toJson());
  }

  @override
  void dispose() {
    _name.dispose();
    _rss.dispose();
    super.dispose();
  }

  Chat get _preview => Chat(
        id: 'preview',
        name: _name.text.trim().isEmpty ? '?' : _name.text.trim(),
        color: _color,
        kind: _kind,
      )..icon = _icon;

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.lightImpact();
    final rss = _rss.text.trim();
    final result = widget.chat ?? Chat(id: uid('c'), name: name, color: _color, kind: _kind);
    result
      ..name = name
      ..icon = _icon
      ..color = _color
      ..kind = _kind
      ..rssUrl = rss.isEmpty ? null : rss
      ..autoCollect = _ac.enabled ? _ac : null;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final p = model.p;
    final tr = model.tr;

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.close, color: p.textSoft), onPressed: () => Navigator.pop(context)),
        title: Text(tr(_editing ? 'edit_chat' : 'new_chat'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        actions: [
          IconButton(
            icon: Icon(Icons.check, color: p.accent),
            tooltip: tr(_editing ? 'save' : 'create'),
            onPressed: _save,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 8),
            Center(child: ChatAvatar(chat: _preview, size: 84, iconSize: 40)),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: !_editing,
              maxLength: 40,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: p.text, fontSize: 15),
              decoration: InputDecoration(
                hintText: tr('chat_name_hint'),
                hintStyle: TextStyle(color: p.textFaint),
                counterText: '',
                filled: true,
                fillColor: p.bgChat,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.accent, width: 1.5)),
              ),
            ),
            _sectionLabel(tr('kind_label'), p),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in chatKinds)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _kind = k.$1);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _kind == k.$1 ? p.accent.withValues(alpha: .18) : p.bgChat,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kind == k.$1 ? p.accent : p.divider, width: 1.5),
                      ),
                      child: Text('${k.$2} ${tr('kind_${k.$1}')}',
                          style: TextStyle(fontSize: 12.5, color: _kind == k.$1 ? p.accent : p.text)),
                    ),
                  ),
              ],
            ),
            if (_kind != 'rss') ...[
              _sectionLabel(tr('ac_title'), p),
              Container(
                decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      value: _ac.enabled,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _ac.enabled = v);
                      },
                      activeThumbColor: p.accent,
                      title: Text(tr('ac_enable'), style: TextStyle(fontSize: 14, color: p.text)),
                      subtitle: Text(tr('ac_hint'),
                          style: TextStyle(fontSize: 11.5, color: p.textFaint)),
                    ),
                    if (_ac.enabled) ...[
                      Divider(height: 1, color: p.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                        child: Text(tr('ac_from'),
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(p, tr('widget_all'), _ac.fromAllChats,
                                () => setState(() { _ac.fromAllChats = true; _ac.sourceFolderId = null; })),
                            for (final f in widget.model.state.folders)
                              _chip(p, f.name, !_ac.fromAllChats && _ac.sourceFolderId == f.id,
                                  () => setState(() { _ac.fromAllChats = false; _ac.sourceFolderId = f.id; })),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                        child: Text(tr('ac_type'),
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final (val, key) in [('all', 'ac_type_all'), ('todo', 'ac_type_todo'), ('note', 'ac_type_note')])
                              _chip(p, tr(key), _ac.typeFilter == val,
                                  () => setState(() => _ac.typeFilter = val)),
                          ],
                        ),
                      ),
                      if (_ac.typeFilter != 'note') ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                          child: Text(tr('ac_due'),
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textFaint)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final (val, key) in [('any', 'ac_due_any'), ('today', 'ac_due_today')])
                                _chip(p, tr(key), _ac.dueFilter == val,
                                    () => setState(() => _ac.dueFilter = val)),
                            ],
                          ),
                        ),
                      ] else
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
            _sectionLabel(tr('icon'), p),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final icon in appIcons)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _icon = icon);
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _icon == icon ? p.accent.withValues(alpha: .18) : p.bgChat,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: _icon == icon ? p.accent : p.divider, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(icon ?? '—', style: TextStyle(fontSize: 16, color: p.text)),
                    ),
                  ),
              ],
            ),
            _sectionLabel(tr('color'), p),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in appColors)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _color = color);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colorFromHex(color),
                        shape: BoxShape.circle,
                        border: _color == color ? Border.all(color: p.text, width: 2) : null,
                      ),
                      child: _color == color ? Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ],
            ),
            if (_kind == 'rss') ...[
              _sectionLabel('RSS Atom', p),
              TextField(
                controller: _rss,
                keyboardType: TextInputType.url,
                style: TextStyle(color: p.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'https://example.com/rss',
                  hintStyle: TextStyle(color: p.textFaint, fontSize: 13),
                  filled: true,
                  fillColor: p.bgChat,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.accent, width: 1.5)),
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(_editing ? Icons.save_outlined : Icons.auto_awesome, size: 19, color: Colors.white),
              label: Text(tr(_editing ? 'save' : 'create'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              onPressed: _save,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, Palette p) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: p.textFaint)),
      );

  Widget _chip(Palette p, String label, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: .18) : p.bgList,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? p.accent : p.divider, width: 1.5),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, color: selected ? p.accent : p.text)),
        ),
      );
}
