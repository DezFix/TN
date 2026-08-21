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
  bool _recLocked = false;
  bool _finishing = false;
  int _recordSec = 0;
  double _dragDx = 0;
  double _dragDy = 0;
  final List<double> _recLevels = [];
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _ampSub;
  Duration _playPos = Duration.zero;
  Duration? _playDur;

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
        _playPos = Duration.zero;
        if (mounted) setState(() {});
      }
    });
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted && _playingId != null) setState(() => _playPos = pos);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (d > Duration.zero) _playDur = d;
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
    _ampSub?.cancel();
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



  Future<void> _beginRecord() async {
    if (_recording || _finishing) return;
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        _toast(widget.model.tr('record_error'), error: true);
        return;
      }
      final tmp = '${Directory.systemTemp.path}${Platform.pathSeparator}${uid('rec')}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: tmp);
      _recordSec = 0;
      _recLevels.clear();
      _dragDx = 0;
      _dragDy = 0;
      _recLocked = false;
      _finishing = false;
      _recording = true;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _recordSec++);
      });
      _ampSub?.cancel();
      _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
        // dBFS: silence ≈ -60, loud ≈ 0
        final level = ((a.max + 60) / 60).clamp(0.05, 1.0);
        if (!mounted) return;
        setState(() {
          _recLevels.add(level);
          if (_recLevels.length > 60) _recLevels.removeAt(0);
        });
      });
      setState(() {});
    } catch (_) {
      _toast(widget.model.tr('record_error'), error: true);
    }
  }

  void _onRecDrag(LongPressMoveUpdateDetails d) {
    if (!_recording || _finishing) return;
    final offset = d.offsetFromOrigin;
    setState(() {
      _dragDx = offset.dx;
      _dragDy = offset.dy;
    });
    if (!_recLocked && offset.dy < -70) {
      setState(() {
        _recLocked = true;
        _dragDx = 0;
        _dragDy = 0;
      });
      HapticFeedback.mediumImpact();
      return;
    }
    if (!_recLocked && offset.dx < -70) {
      _finishRecord(send: false);
    }
  }

  void _endRecPress(LongPressEndDetails d) {
    if (!_recording || _finishing) return;
    if (_recLocked) return; // keep recording while locked
    _finishRecord(send: true);
  }

  List<int> _downsampleWaveform(List<double> levels, int target) {
    if (levels.isEmpty) return const <int>[];
    final out = <int>[];
    final step = levels.length / target;
    for (var i = 0; i < target; i++) {
      final start = (i * step).floor();
      var end = ((i + 1) * step).ceil();
      if (end <= start) end = start + 1;
      var peak = 0.0;
      for (var j = start; j < end && j < levels.length; j++) {
        if (levels[j] > peak) peak = levels[j];
      }
      out.add(((peak * 100).round()).clamp(6, 100));
    }
    return out;
  }

  Future<void> _finishRecord({required bool send}) async {
    if (!_recording || _finishing) return;
    _finishing = true;
    _recordTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    final secs = _recordSec;
    final levels = List<double>.of(_recLevels);
    final wasLocked = _recLocked;
    _recording = false;
    _recLocked = false;
    _recLevels.clear();
    _dragDx = 0;
    _dragDy = 0;
    if (mounted) setState(() {});

    if (!send) {
      await _deleteTemp(path);
      _finishing = false;
      return;
    }
    if (path == null || path.isEmpty || secs < 1) {
      await _deleteTemp(path);
      _finishing = false;
      if (secs < 1 && wasLocked == false) _toast(widget.model.tr('rec_too_short'));
      return;
    }
    try {
      final name = await MediaStore().saveFile(path, 'audio');
      widget.model.state.entries.add(Entry(
        id: uid('e'),
        chatId: widget.chatId,
        type: 'audio',
        ts: DateTime.now().millisecondsSinceEpoch,
        media: name,
        duration: secs,
        waveform: _downsampleWaveform(levels, 40),
      ));
      await widget.model.save();
      if (mounted) setState(() {});
    } catch (_) {}
    await _deleteTemp(path);
    _finishing = false;
  }

  Future<void> _deleteTemp(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _playAudio(Entry entry) async {
    final path = await MediaStore().pathOf(entry.media!);
    if (_playingId == entry.id) {
      await _audioPlayer.stop();
      setState(() {
        _playingId = null;
        _playPos = Duration.zero;
      });
      return;
    }
    setState(() {
      _playingId = entry.id;
      _playPos = Duration.zero;
    });
    await _audioPlayer.play(DeviceFileSource(path));
  }

  Future<void> _scheduleTextAt(Offset globalPos) async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final model = widget.model;
    final option = await showSendMenuPopup(context, model, globalPos);
    if (option == null || !mounted) return;

    DateTime? when;
    String? recurrence;
    List<int>? days;

    switch (option) {
      case SendOption.later:
        when = await showReminderPicker(context, model);
      case SendOption.daily:
        if (!mounted) return;
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
        if (time == null) return;
        final now = DateTime.now();
        var next = DateTime(now.year, now.month, now.day, time.hour, time.minute);
        if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
        when = next;
        recurrence = 'daily';
      case SendOption.weekly:
        final picked = await showWeekdayPickerDialog(context, model, const []);
        if (picked == null || picked.isEmpty || !mounted) return;
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
        if (time == null) return;
        final now = DateTime.now();
        var cand = DateTime(now.year, now.month, now.day, time.hour, time.minute);
        do {
          cand = cand.add(const Duration(days: 1));
        } while (!picked.contains(cand.weekday));
        when = cand;
        recurrence = 'weekly';
        days = picked;
    }

    if (when == null) return;
    final whenMs = when.millisecondsSinceEpoch;
    final entry = Entry(
      id: uid('e'),
      chatId: widget.chatId,
      type: 'text',
      ts: DateTime.now().millisecondsSinceEpoch,
      text: text,
      tags: extractTags(text),
      scheduledAt: whenMs,
      recurrence: recurrence,
      recurrenceDays: days,
    );
    _text.clear();
    model.state.entries.add(entry);
    await model.save();
    // Fallback notification in case the app is closed at send time.
    await RemindersService.instance.requestPermissions();
    await RemindersService.instance.schedule(
      Reminder(id: entry.id, chatId: widget.chatId, when: whenMs),
      widget.model.tr('sched_notif_title'),
      widget.model.tr('sched_notif_body', [_chat.name]),
    );
    if (mounted) {
      setState(() {});
      _toast(widget.model.tr(
        'scheduled_at',
        ['${fmtDay(whenMs, widget.model.tr)} ${fmtTime(whenMs)}'],
      ));
    }
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
      case EntryAction.cancelSchedule:
        await RemindersService.instance.cancelById(entry.id.hashCode);
        await MediaStore().remove(entry.media);
        widget.model.state.entries.removeWhere((e) => e.id == entry.id);
        await widget.model.save();
        if (mounted) {
          setState(() {});
          _toast(widget.model.tr('cancel_schedule_done'));
        }
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
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopbar(chat),
                Expanded(child: _buildMessages(model)),
                _buildComposer(),
              ],
            ),
            if (_recording) Positioned(left: 0, right: 0, bottom: 0, child: _buildRecordingPanel()),
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
          PopupMenuButton<ChatTopAction>(
            icon: Icon(Icons.more_vert, color: p.textSoft),
            color: p.modalBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) async {
              switch (v) {
                case ChatTopAction.remind:
                  await _setReminder();
                  break;
                case ChatTopAction.edit:
                  await _editChat();
                  break;
                case ChatTopAction.delete:
                  await _deleteChat();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: ChatTopAction.remind, child: Row(children: [Icon(Icons.alarm, size: 18, color: p.accent), const SizedBox(width: 10), Text(widget.model.tr('remind'), style: TextStyle(color: p.text))])),
              PopupMenuItem(value: ChatTopAction.edit, child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(widget.model.tr('edit_chat'), style: TextStyle(color: p.text))])),
              PopupMenuItem(value: ChatTopAction.delete, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: p.danger), const SizedBox(width: 10), Text(widget.model.tr('delete'), style: TextStyle(color: p.danger))])),
            ],
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
      child: entry.isScheduled
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: .15),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.recurrence == null ? Icons.schedule : Icons.repeat,
                        size: 13,
                        color: p.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        model.tr('scheduled_at', [
                          '${fmtDay(entry.scheduledAt!, model.tr)} ${fmtTime(entry.scheduledAt!)}',
                        ]),
                        style: TextStyle(fontSize: 11, color: p.accent, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Opacity(opacity: .75, child: content),
              ],
            )
          : content,
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
    final dur = entry.duration ?? 0;
    final total = _playDur?.inMilliseconds ?? dur * 1000;
    final progress =
        playing && total > 0 ? (_playPos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    String two(int v) => v.toString().padLeft(2, '0');
    final posLabel = '${_playPos.inMinutes}:${two(_playPos.inSeconds % 60)}';
    return Container(
      width: 250,
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
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle,
                    color: p.accent, size: 32),
                onPressed: () => _playAudio(entry),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StaticWaveform(
                  samples: entry.waveform ?? const <int>[],
                  progress: progress,
                  playedColor: p.accent,
                  restColor: p.textFaint.withValues(alpha: .45),
                ),
              ),
            ],
          ),
          Text(
            playing
                ? '$posLabel · ${model.tr('playing')}'
                : '${entry.duration ?? 0} ${model.tr('sec')} · ${fmtTime(entry.ts)}',
            style: TextStyle(fontSize: 11, color: p.textFaint),
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
          PopupMenuButton<AttachOption>(
            icon: Icon(Icons.attach_file, color: p.textSoft),
            color: p.modalBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tooltip: 'attach',
            onSelected: (v) async {
              switch (v) {
                case AttachOption.photo:
                  await _pickImage();
                  break;
                case AttachOption.todo:
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
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: AttachOption.photo, child: Row(children: [Icon(Icons.photo_outlined, size: 18, color: p.accent), const SizedBox(width: 10), Text(model.tr('attach_photo'), style: TextStyle(color: p.text))])),
              PopupMenuItem(value: AttachOption.todo, child: Row(children: [Icon(Icons.checklist, size: 18, color: p.accent), const SizedBox(width: 10), Text(model.tr('attach_todo'), style: TextStyle(color: p.text))])),
            ],
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
          if (_text.text.isNotEmpty)
            GestureDetector(
              onLongPressStart: (d) => _scheduleTextAt(d.globalPosition),
              child: IconButton.filled(
                icon: const Icon(Icons.send, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: p.accent),
                onPressed: _sendText,
              ),
            )
          else
            GestureDetector(
              onLongPressStart: (d) => _beginRecord(),
              onLongPressMoveUpdate: _onRecDrag,
              onLongPressEnd: _endRecPress,
              onLongPressCancel: () => _finishRecord(send: true),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                child: Icon(Icons.mic, color: Colors.white, size: 24),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingPanel() {
    final model = widget.model;
    final lockProgress = (-_dragDy / 70).clamp(0.0, 1.0);
    final cancelProgress = (-_dragDx / 70).clamp(0.0, 1.0);

    String two(int v) => v.toString().padLeft(2, '0');
    final timeLabel = '${(_recordSec / 60).floor()}:${two(_recordSec % 60)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      color: p.bgList,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_recLocked) ...[
            Opacity(
              opacity: lockProgress,
              child: Column(
                children: [
                  Icon(Icons.lock, color: p.accent, size: 22),
                  Text(model.tr('rec_lock_hint'),
                      style: TextStyle(fontSize: 11, color: p.textSoft)),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              if (_recLocked)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: p.danger, size: 26),
                  tooltip: model.tr('rec_cancel'),
                  onPressed: () => _finishRecord(send: false),
                )
              else
                Opacity(
                  opacity: cancelProgress,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, color: p.danger, size: 24),
                      const SizedBox(width: 4),
                      Text(model.tr('rec_cancel'),
                          style: TextStyle(fontSize: 12.5, color: p.danger)),
                    ],
                  ),
                ),
              const Spacer(),
              Icon(Icons.fiber_manual_record, color: p.danger, size: 14),
              const SizedBox(width: 6),
              Text(timeLabel,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(width: 10),
              _LiveWaveform(levels: _recLevels, color: p.accent),
              const Spacer(),
              if (_recLocked)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  icon: const Icon(Icons.send, size: 18, color: Colors.white),
                  label: Text(model.tr('record_stop')),
                  onPressed: () => _finishRecord(send: true),
                )
              else
                Opacity(
                  opacity: .9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic, color: p.textFaint, size: 20),
                      const SizedBox(width: 4),
                      Text(model.tr('record_start'),
                          style: TextStyle(fontSize: 12, color: p.textFaint)),
                    ],
                  ),
                ),
            ],
          ),
          if (_recLocked) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, color: p.accent, size: 13),
                const SizedBox(width: 4),
                Text(model.tr('rec_locked'),
                    style: TextStyle(fontSize: 11.5, color: p.textSoft)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveWaveform extends StatelessWidget {
  const _LiveWaveform({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final shown = levels.length > 36 ? levels.sublist(levels.length - 36) : levels;
    return SizedBox(
      height: 30,
      width: 120,
      child: CustomPaint(
        painter: _WaveformPainter(
          samples: shown.map((l) => (l * 100).round().clamp(6, 100)).toList(),
          progress: 1,
          playedColor: color,
          restColor: color.withValues(alpha: .35),
          barWidth: 2.5,
          gap: 1,
        ),
      ),
    );
  }
}

class _StaticWaveform extends StatelessWidget {
  const _StaticWaveform({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.restColor,
  });

  final List<int> samples;
  final double progress;
  final Color playedColor;
  final Color restColor;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Container(
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: restColor,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return SizedBox(
      height: 30,
      child: CustomPaint(
        painter: _WaveformPainter(
          samples: samples,
          progress: progress,
          playedColor: playedColor,
          restColor: restColor,
          barWidth: 2.5,
          gap: 1.5,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.restColor,
    required this.barWidth,
    required this.gap,
  });

  final List<int> samples;
  final double progress;
  final Color playedColor;
  final Color restColor;
  final double barWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final step = barWidth + gap;
    final count = (size.width / step).floor();
    final paintPlayed = Paint()..color = playedColor;
    final paintRest = Paint()..color = restColor;
    for (var i = 0; i < count; i++) {
      // stretch/compress sample list to fit the available width
      final idx = (i * samples.length / count).floor().clamp(0, samples.length - 1);
      final h = (samples[idx] / 100) * size.height;
      final x = i * step;
      final rect = Rect.fromLTWH(x, (size.height - h) / 2, barWidth, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        (i / count) < progress ? paintPlayed : paintRest,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.samples != samples ||
      old.progress != progress ||
      old.playedColor != playedColor ||
      old.restColor != restColor;
}