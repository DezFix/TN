import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../src/app_model.dart';
import '../src/dialogs.dart';
import '../src/media.dart';
import '../src/models.dart';
import '../src/reminders.dart';
import '../src/theme.dart';
import '../src/widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.model,
    required this.chatId,
    this.scrollToEntryId,
    this.highlightEntryId,
  });

  final AppModel model;
  final String chatId;
  final String? scrollToEntryId;
  final String? highlightEntryId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _editText = TextEditingController();
  final _imagePicker = ImagePicker();
  final _audioPlayer = AudioPlayer();
  final _recorder = AudioRecorder();

  String? _editingId;
  String? _highlightId;
  String? _playingId;
  bool _recording = false;
  int _recordSec = 0;
  Timer? _recordTimer;
  String? _recordPath;

  Chat get _chat => widget.model.state.chatById(widget.chatId)!;
  Palette get p => widget.model.p;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
    _highlightId = widget.highlightEntryId;
    _audioPlayer.onPlayerStateChanged.listen((s) {
      if (s == PlayerState.completed && _playingId != null) {
        _playingId = null;
        if (mounted) setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    _text.dispose();
    _editText.dispose();
    _audioPlayer.dispose();
    _recorder.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  void _scrollToTarget() {
    final target = widget.scrollToEntryId;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _bubbleContexts[target];
      if (ctx == null) return;
      await Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          alignment: .3);
      _highlightId = target;
      if (mounted) setState(() {});
      await Future.delayed(const Duration(seconds: 4));
      if (mounted && _highlightId == target) setState(() => _highlightId = null);
    });
  }

  final Map<String, BuildContext> _bubbleContexts = {};

  // ---------------- actions ----------------

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    widget.model.state.entries.add(Entry(
      id: uid('e'),
      chatId: widget.chatId,
      type: 'text',
      ts: DateTime.now().millisecondsSinceEpoch,
      text: text,
      tags: extractTags(text),
    ));
    await widget.model.save();
    setState(() {});
  }

  Future<void> _pickImage() async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final name = await MediaStore().saveImage(file.path);
      widget.model.state.entries.add(Entry(
        id: uid('e'),
        chatId: widget.chatId,
        type: 'image',
        ts: DateTime.now().millisecondsSinceEpoch,
        media: name,
        mediaName: name,
      ));
      await widget.model.save();
      if (mounted) setState(() {});
    } catch (_) {
      _toast(widget.model.tr('photo_error'), error: true);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      final name = await MediaStore().saveFile(file.path, 'video');
      final size = await File(file.path).length();
      widget.model.state.entries.add(Entry(
        id: uid('e'),
        chatId: widget.chatId,
        type: 'video',
        ts: DateTime.now().millisecondsSinceEpoch,
        media: name,
        mediaName: file.name,
        mediaSize: '${humanSize(size)} ${widget.model.tr('mb')}',
      ));
      await widget.model.save();
      if (mounted) setState(() {});
    } catch (_) {
      _toast(widget.model.tr('video_error'), error: true);
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecord();
      return;
    }
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        _toast(widget.model.tr('record_error'), error: true);
        return;
      }
      final tmp = '${Directory.systemTemp.path}${Platform.pathSeparator}${uid('rec')}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: tmp);
      _recordPath = tmp;
      _recordSec = 0;
      _recording = true;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _recordSec++);
      });
      setState(() {});
    } catch (_) {
      _toast(widget.model.tr('record_error'), error: true);
    }
  }

  Future<void> _stopRecord() async {
    _recordTimer?.cancel();
    try {
      final path = await _recorder.stop();
      final secs = _recordSec;
      _recording = false;
      setState(() {});
      if (path != null && path.isNotEmpty && secs > 0) {
        final name = await MediaStore().saveFile(path, 'audio');
        widget.model.state.entries.add(Entry(
          id: uid('e'),
          chatId: widget.chatId,
          type: 'audio',
          ts: DateTime.now().millisecondsSinceEpoch,
          media: name,
          duration: secs,
        ));
        await widget.model.save();
        if (mounted) setState(() {});
      }
      if (_recordPath != null) {
        final f = File(_recordPath!);
        if (await f.exists()) await f.delete();
        _recordPath = null;
      }
    } catch (_) {}
  }

  Future<void> _playAudio(Entry entry) async {
    final path = await MediaStore().pathOf(entry.media!);
    if (_playingId == entry.id) {
      await _audioPlayer.stop();
      setState(() => _playingId = null);
      return;
    }
    setState(() => _playingId = entry.id);
    await _audioPlayer.play(DeviceFileSource(path));
  }

  void _showImage(Entry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FutureBuilder<String>(
        future: MediaStore().pathOf(entry.media!),
        builder: (ctx, snap) {
          if (!snap.hasData) return const SizedBox();
          return Scaffold(
            backgroundColor: Colors.black,
            body: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Center(
                child: InteractiveViewer(child: Image.file(File(snap.data!))),
              ),
            ),
          );
        },
      ),
    ));
  }

  Future<void> _editChat() async {
    final result = await showChatEditDialog(context, widget.model, chat: _chat);
    if (result == null) return;
    await widget.model.save();
    setState(() {});
  }

  Future<void> _setReminder() async {
    final when = await showReminderPicker(context, widget.model);
    if (when == null) return;
    final r = Reminder(
        id: uid('rm'), chatId: widget.chatId, when: when.millisecondsSinceEpoch);
    widget.model.state.reminders.add(r);
    await widget.model.save();
    await RemindersService.instance.requestPermissions();
    await RemindersService.instance.schedule(
      r,
      widget.model.tr('remind_title', [_chat.name]),
      widget.model.tr('remind_body'),
    );
    _toast(widget.model.tr('remind_set'));
  }

  Future<void> _deleteChat() async {
    final ok = await showDeleteChatDialog(context, widget.model);
    if (ok != true) return;
    for (final e in widget.model.state.entriesFor(widget.chatId)) {
      await MediaStore().remove(e.media);
    }
    for (final r in widget.model.state.reminders.toList()) {
      if (r.chatId == widget.chatId) {
        await RemindersService.instance.cancel(r);
        widget.model.state.reminders.remove(r);
      }
    }
    widget.model.state.entries.removeWhere((e) => e.chatId == widget.chatId);
    widget.model.state.chats.removeWhere((c) => c.id == widget.chatId);
    await widget.model.save();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _onCtxAction(Entry entry, EntryAction action) async {
    switch (action) {
      case EntryAction.copy:
        final text = entry.type == 'todo'
            ? (entry.items ?? const <TodoItem>[])
                .map((i) => '${i.done ? '☑' : '☐'} ${i.text}')
                .join('\n')
            : entry.text;
        await Clipboard.setData(ClipboardData(text: text));
        _toast(widget.model.tr('copied'));
      case EntryAction.edit:
        if (entry.type == 'todo') {
          final items = await showTodoEditorDialog(context, widget.model, entry: entry);
          if (items == null) return;
          entry.items = items;
          await widget.model.save();
          if (mounted) setState(() {});
        } else {
          _editText.text = entry.text;
          setState(() => _editingId = entry.id);
        }
      case EntryAction.forward:
        final target = await showForwardDialog(context, widget.model);
        if (target == null || target.id == widget.chatId) return;
        final copy = Entry(
          id: uid('e'),
          chatId: target.id,
          type: entry.type,
          ts: DateTime.now().millisecondsSinceEpoch,
          text: entry.text,
          tags: List.of(entry.tags),
          media: entry.media,
          mediaName: entry.mediaName,
          mediaSize: entry.mediaSize,
          duration: entry.duration,
          items: entry.items?.map((i) => TodoItem(id: i.id, text: i.text, done: i.done)).toList(),
        );
        widget.model.state.entries.add(copy);
        await widget.model.save();
        _toast(widget.model.tr('forwarded_to', [target.name]));
      case EntryAction.delete:
        final ok = await showDeleteEntryDialog(context, widget.model);
        if (ok != true) return;
        await MediaStore().remove(entry.media);
        widget.model.state.entries.removeWhere((e) => e.id == entry.id);
        await widget.model.save();
        if (mounted) setState(() {});
    }
  }

  Future<void> _saveEdit(Entry entry) async {
    final text = _editText.text.trim();
    if (text.isEmpty) return;
    entry.text = text;
    entry.tags = extractTags(text);
    _editingId = null;
    _editText.clear();
    await widget.model.save();
    setState(() {});
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 2500),
      backgroundColor: error ? const Color(0xFF3A2020) : p.bgChat,
    ));
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final chat = _chat;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopbar(chat),
            Expanded(child: _buildMessages(model)),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopbar(Chat chat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      color: p.bgList,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: p.textSoft),
            onPressed: () => Navigator.of(context).pop(),
          ),
          GestureDetector(
            onTap: _editChat,
            child: Row(
              children: [
                ChatAvatar(chat: chat, size: 38, iconSize: 18),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 170,
                      child: Text(chat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: p.text)),
                    ),
                    Text(widget.model.tr('chat_subtitle'),
                        style: TextStyle(fontSize: 11.5, color: p.textFaint)),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.alarm, color: p.textSoft),
            tooltip: widget.model.tr('remind'),
            onPressed: _setReminder,
          ),
          IconButton(
            icon: Icon(Icons.edit, color: p.textSoft),
            tooltip: widget.model.tr('edit_chat'),
            onPressed: _editChat,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: p.textSoft),
            tooltip: widget.model.tr('delete'),
            onPressed: _deleteChat,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(AppModel model) {
    final entries = sortedEntriesFor(model.state, widget.chatId);
    final tr = model.tr;
    _bubbleContexts.clear();

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('no_messages'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: p.textFaint, height: 1.5)),
        ),
      );
    }

    final children = <Widget>[];
    String? lastDay;
    for (final e in entries) {
      final day = fmtDay(e.ts, tr);
      if (day != lastDay) {
        lastDay = day;
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: DayPill(label: day, p: p),
        ));
      }
      final highlight = _highlightId == e.id;
      final bubble = Builder(builder: (ctx) {
        _bubbleContexts[e.id] = ctx;
        return _buildBubble(model, e, highlight: highlight);
      });
      children.add(GestureDetector(
        onLongPress: () async {
          final action = await showEntryCtxSheet(context, model, e);
          if (action != null) await _onCtxAction(e, action);
        },
        onSecondaryTapDown: (_) async {
          final action = await showEntryCtxSheet(context, model, e);
          if (action != null) await _onCtxAction(e, action);
        },
        child: bubble,
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      reverse: true,
      children: children.reversed.toList(),
    );
  }

  Widget _buildBubble(AppModel model, Entry entry, {required bool highlight}) {
    final Widget content = switch (entry.type) {
      'text' => _buildTextBubble(model, entry),
      'image' => _buildImageBubble(model, entry),
      'audio' => _buildAudioBubble(model, entry),
      'video' => _buildVideoBubble(model, entry),
      'todo' => _buildTodoBubble(model, entry),
      _ => const SizedBox(),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlight ? p.accent : Colors.transparent,
          width: 2,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(3),
        ),
      ),
      child: content,
    );
  }

  Widget _buildTextBubble(AppModel model, Entry entry) {
    if (_editingId == entry.id) {
      final field = TextField(
        controller: _editText,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        style: TextStyle(color: p.text, fontSize: 14.5),
        decoration: InputDecoration(
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: p.accent)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: p.accent)),
        ),
      );
      return Container(
        width: 320,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: p.bubbleOwn,
          border: Border.all(color: p.bubbleBorder),
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            field,
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => setState(() => _editingId = null),
                  child: Text(model.tr('cancel'), style: TextStyle(color: p.textSoft)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  onPressed: () => _saveEdit(entry),
                  child: Text(model.tr('save')),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final spans = _highlightTags(entry.text, p);
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: p.bubbleOwn,
        border: Border.all(color: p.bubbleBorder),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText.rich(
              TextSpan(children: spans),
              style: TextStyle(fontSize: 14.5, color: p.text, height: 1.35),
            ),
          ),
          Text(fmtTime(entry.ts),
              style: TextStyle(fontSize: 10.5, color: p.textFaint)),
        ],
      ),
    );
  }

  List<TextSpan> _highlightTags(String text, Palette p) {
    final spans = <TextSpan>[];
    final re = RegExp(r'#[\wа-яёіїєґА-ЯЁІЇЄҐ]+');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  Widget _buildImageBubble(AppModel model, Entry entry) {
    return GestureDetector(
      onTap: () => _showImage(entry),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 340),
        decoration: BoxDecoration(
          border: Border.all(color: p.bubbleBorder),
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FutureBuilder<String>(
              future: MediaStore().pathOf(entry.media!),
              builder: (ctx, snap) => snap.hasData
                  ? SizedBox(
                      width: 260,
                      height: 300,
                      child: Image.file(File(snap.data!), fit: BoxFit.cover),
                    )
                  : const SizedBox(width: 260, height: 300),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Text(fmtTime(entry.ts),
                  style: TextStyle(fontSize: 10.5, color: p.textFaint)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioBubble(AppModel model, Entry entry) {
    final playing = _playingId == entry.id;
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: p.bubbleOwn,
        border: Border.all(color: p.bubbleBorder),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(playing ? Icons.stop_circle : Icons.play_circle,
                    color: p.accent, size: 32),
                onPressed: () => _playAudio(entry),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.tr('voice_message'),
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500, color: p.text)),
                    Text(
                      '${playing ? model.tr('playing') : '${entry.duration ?? 0} ${model.tr('sec')}'} · ${fmtTime(entry.ts)}',
                      style: TextStyle(fontSize: 11, color: p.textFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVideoBubble(AppModel model, Entry entry) {
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.bubbleOwn,
        border: Border.all(color: p.bubbleBorder),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.videocam, color: p.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry.mediaName ?? model.tr('video'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500, color: p.text)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${entry.mediaSize ?? ''} · ${fmtTime(entry.ts)}',
              style: TextStyle(fontSize: 11, color: p.textFaint)),
        ],
      ),
    );
  }

  Widget _buildTodoBubble(AppModel model, Entry entry) {
    final items = entry.items ?? const <TodoItem>[];
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 7),
      decoration: BoxDecoration(
        color: p.bubbleOwn,
        border: Border.all(color: p.bubbleBorder),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in items)
            Row(
              children: [
                Checkbox(
                  value: item.done,
                  activeColor: p.accent,
                  onChanged: (_) async {
                    item.done = !item.done;
                    await model.save();
                    if (mounted) setState(() {});
                  },
                ),
                Expanded(
                  child: Text(
                    item.text,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: p.text,
                      decoration: item.done ? TextDecoration.lineThrough : null,
                      decorationColor: p.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          Text(fmtTime(entry.ts), style: TextStyle(fontSize: 10.5, color: p.textFaint)),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final model = widget.model;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      color: p.bgList,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file, color: p.textSoft),
            onPressed: _pickImage,
          ),
          IconButton(
            icon: Icon(Icons.videocam, color: p.textSoft),
            onPressed: _pickVideo,
          ),
          IconButton(
            icon: Icon(Icons.checklist, color: p.textSoft),
            onPressed: () async {
              final items = await showTodoEditorDialog(context, model);
              if (items == null || items.isEmpty) return;
              model.state.entries.add(Entry(
                id: uid('e'),
                chatId: widget.chatId,
                type: 'todo',
                ts: DateTime.now().millisecondsSinceEpoch,
                items: items,
              ));
              await model.save();
              if (mounted) setState(() {});
            },
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: p.bgChat,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _text,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: p.text, fontSize: 14.5),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: model.tr('message_hint'),
                  hintStyle: TextStyle(color: p.textFaint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (_recording)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.danger),
              onPressed: _toggleRecord,
              child: Text('${model.tr('record_stop')} $_recordSec'),
            )
          else if (_text.text.isNotEmpty)
            IconButton.filled(
              icon: const Icon(Icons.send, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: p.accent),
              onPressed: _sendText,
            )
          else
            IconButton(
              icon: Icon(Icons.mic, color: p.textSoft),
              tooltip: model.tr('record_start'),
              onPressed: _toggleRecord,
            ),
        ],
      ),
    );
  }
}