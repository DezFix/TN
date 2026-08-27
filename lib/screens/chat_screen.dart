// ignore_for_file: unnecessary_non_null_assertion
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/app_model.dart';
import '../src/dialogs.dart';
import '../src/link_preview.dart';
import '../src/media.dart';
import '../src/models.dart';
import '../src/reminders.dart';
import '../src/rss.dart';
import '../src/share_service.dart';
import '../src/sound.dart';
import '../src/theme.dart';
import '../src/undo.dart';
import '../src/undo_toast.dart';
import '../src/widgets.dart';
import 'chat_edit_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';

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
  final _searchCtrl = TextEditingController();
  final _listCtrl = ScrollController();
  bool _searching = false;
  String _searchQuery = '';
  final Set<String> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;
  final _imagePicker = ImagePicker();
  final _audioPlayer = AudioPlayer();
  final _recorder = AudioRecorder();

  String? _editingId;
  String? _highlightId;
  String? _playingId;
  String? _pendingImagePath;
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

  Chat? get _chatOrNull => widget.model.state.chatById(widget.chatId);
  Chat get _chat => _chatOrNull!;
  Palette get p => widget.model.p;

  /// Cached media path / link preview futures — a FutureBuilder that
  /// re-creates its future on every build restarts the work each time.
  final Map<String, Future<String>> _pathFutures = {};
  final Map<String, Future<LinkPreviewData?>> _previewFutures = {};
  final List<GestureRecognizer> _recognizers = [];

  Future<String> _pathOf(String media) =>
      _pathFutures.putIfAbsent(media, () => MediaStore().pathOf(media));

  Future<LinkPreviewData?> _previewFor(String url) => _previewFutures
      .putIfAbsent(url, () => LinkPreview.fetch(url));

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
    _highlightId = widget.highlightEntryId;
    _loadDraft();
    _text.addListener(_saveDraft);
    _audioPlayer.onPlayerStateChanged.listen((s) {
      if (s == PlayerState.completed && _playingId != null) {
        _playingId = null;
        _playPos = Duration.zero;
        _playDur = null;
        if (mounted) setState(() {});
      }
    });
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted && _playingId != null) setState(() => _playPos = pos);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (d > Duration.zero) _playDur = d;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scrollToEntryId == null) _scrollToBottom(animate: false);
      _scrollToTarget();
    });
    final chat = _chatOrNull;
    if (chat != null && chat.rssUrl != null && chat.rssUrl!.isNotEmpty) {
      RssService.fetchForChat(chat, widget.model.state).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    _text.removeListener(_saveDraft);
    _text.dispose();
    _editText.dispose();
    _searchCtrl.dispose();
    _listCtrl.dispose();
    _audioPlayer.dispose();
    _recorder.dispose();
    _recordTimer?.cancel();
    _ampSub?.cancel();
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// Pins the reversed list to its offset-0 edge == visual bottom, so newly
  /// sent messages are always visible appearing from the bottom.
  void _scrollToBottom({bool animate = true}) {
    if (!_listCtrl.hasClients) return;
    if (animate) {
      _listCtrl.animateTo(0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    } else {
      _listCtrl.jumpTo(0);
    }
  }
  void _onModel() {
    if (mounted) setState(() {});
  }

  // ---- drafts ----

  String get _draftKey => 'tn-draft-${widget.chatId}';

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = prefs.getString(_draftKey);
      if (draft != null && draft.isNotEmpty && mounted) {
        _text.text = draft;
      }
    } catch (_) {}
  }

  void _saveDraft() {
    final text = _text.text;
    SharedPreferences.getInstance().then((prefs) {
      if (text.isEmpty) {
        prefs.remove(_draftKey);
      } else {
        prefs.setString(_draftKey, text);
      }
    });
  }

  void _clearDraft() {
    SharedPreferences.getInstance().then((prefs) => prefs.remove(_draftKey));
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

  /// Due chip: today shows only the time, other days a compact numeric date.
  String _fmtDue(int ms, String Function(String, [List<String>?]) tr) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = d.year == now.year && d.month == now.month && d.day == now.day;
    String two(int v) => v.toString().padLeft(2, '0');
    final date = d.year == now.year
        ? '${d.day}.${two(d.month)}'
        : '${d.day}.${two(d.month)}.${d.year % 100}';
    return today ? fmtTime(ms) : '$date ${fmtTime(ms)}';
  }

  // ---------------- actions ----------------

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    _clearDraft();
    final isTasksChat = _chat.kind == 'tasks';
    widget.model.state.entries.add(Entry(
      id: uid('e'),
      chatId: widget.chatId,
      type: isTasksChat ? 'todo' : 'text',
      ts: DateTime.now().millisecondsSinceEpoch,
      text: isTasksChat ? '' : text,
      items: isTasksChat ? [TodoItem(id: uid('t'), text: text)] : null,
      tags: extractTags(text),
    ));
    HapticFeedback.lightImpact();
    if (mounted) setState(() {});
    widget.model.save();
  }

  /// Date/time/recurrence pipeline shared by attach-todo and long-press send.
  Future<({int? dueAt, String? recurrence, List<int>? recurrenceDays, int? monthDay})>
      _pickTaskSchedule() async {
    if (!mounted) return (dueAt: null, recurrence: null, recurrenceDays: null, monthDay: null);
    final res = await showScheduleSheet(context, widget.model);
    return (
      dueAt: res?.dueAt,
      recurrence: res?.recurrence,
      recurrenceDays: res?.recurrenceDays,
      monthDay: res?.monthDay,
    );
  }

  Future<void> _scheduleEntryReminder(Entry entry) async {
    if (entry.dueAt == null) return;
    await RemindersService.instance.requestPermissions();
    await RemindersService.instance.schedule(
      Reminder(id: entry.id, chatId: widget.chatId, when: entry.dueAt!),
      widget.model.tr('remind_title', [_chat.name]),
      widget.model.tr('remind_body'),
      snoozeLabels: [
        widget.model.tr('snooze_10m'),
        widget.model.tr('snooze_1h')
      ],
    );
  }

  /// Long-press send in tasks chats: create the task with an explicit
  /// due date/time instead of sending it undated.
  /// In note chats: create a text entry with a reminder (notification only,
  /// not shown in the widget).
  Future<void> _sendTextWithDate() async {
    final text = _text.text.trim();
    if (text.isEmpty || _pendingImagePath != null) return;
    HapticFeedback.mediumImpact();
    final sched = await _pickTaskSchedule();
    if (!mounted || sched.dueAt == null) return;
    final isTasks = _chat.kind == 'tasks';
    final entry = Entry(
      id: uid('e'),
      chatId: widget.chatId,
      type: isTasks ? 'todo' : 'text',
      ts: DateTime.now().millisecondsSinceEpoch,
      items: isTasks ? [TodoItem(id: uid('t'), text: text)] : null,
      text: isTasks ? '' : text,
      tags: extractTags(text),
      dueAt: sched.dueAt,
      recurrence: sched.recurrence,
      recurrenceDays: sched.recurrenceDays == null ? null : List.of(sched.recurrenceDays!),
      monthDay: sched.monthDay,
    );
    widget.model.state.entries.add(entry);
    _text.clear();
    _clearDraft();
    if (mounted) setState(() {});
    await _scheduleEntryReminder(entry);
    widget.model.save();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      HapticFeedback.lightImpact();
      setState(() => _pendingImagePath = file.path);
    } catch (_) {
      _toast(widget.model.tr('photo_error'), error: true);
    }
  }

  Future<void> _showAttachSheet(AppModel model) async {
    final p = model.p;
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.modalBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 16),
              decoration: BoxDecoration(color: p.textFaint.withValues(alpha: .3), borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Icon(Icons.photo_outlined, color: p.accent),
              title: Text(model.tr('attach_photo'), style: TextStyle(color: p.text)),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file_outlined, color: p.accent),
              title: Text(model.tr('attach_doc'), style: TextStyle(color: p.text)),
              onTap: () => Navigator.pop(ctx, 'doc'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result == 'photo') {
      await _pickImage();
    } else if (result == 'doc') {
      await _pickDocument();
    }
  }

  Future<void> _pickDocument() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        XTypeGroup(label: 'documents', extensions: ['pdf', 'txt', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'json', 'xml', 'html', 'md', 'zip', 'rar']),
      ]);
      if (file == null) return;
      HapticFeedback.lightImpact();
      // Save to media store and create doc entry directly.
      final stored = await MediaStore().saveFile(file.path, 'file');
      final size = await File(file.path).length();
      final name = file.name;
      final entry = Entry(
        id: uid('e'),
        chatId: widget.chatId,
        type: 'doc',
        ts: DateTime.now().millisecondsSinceEpoch,
        media: stored,
        mediaName: name,
        mediaSize: _fmtDocSize(size),
      );
      widget.model.state.entries.add(entry);
      if (mounted) setState(() {});
      widget.model.save();
    } catch (_) {
      _toast(widget.model.tr('cant_open_file'), error: true);
    }
  }

  String _fmtDocSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Future<void> _sendPendingImage() async {
    final tmp = _pendingImagePath;
    if (tmp == null) return;
    final caption = _text.text.trim();
    _text.clear();
    _clearDraft();
    setState(() => _pendingImagePath = null);
    try {
      final store = MediaStore();
      final name = await store.quickCopy(tmp);
      widget.model.state.entries.add(Entry(
        id: uid('e'),
        chatId: widget.chatId,
        type: 'image',
        ts: DateTime.now().millisecondsSinceEpoch,
        text: caption,
        tags: extractTags(caption),
        media: name,
        mediaName: name,
      ));
      HapticFeedback.lightImpact();
      if (mounted) setState(() {});
      widget.model.save();
      store.optimizeImage(name);
    } catch (_) {
      _toast(widget.model.tr('photo_error'), error: true);
    }
  }

  Future<void> _submitComposer() async {
    if (_pendingImagePath != null) {
      await _sendPendingImage();
      return;
    }
    await _sendText();
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
    if (entry.media == null) return;
    final path = await _pathOf(entry.media!);
    if (_playingId == entry.id) {
      await _audioPlayer.stop();
      setState(() {
        _playingId = null;
        _playPos = Duration.zero;
        _playDur = null;
      });
      return;
    }
    setState(() {
      _playingId = entry.id;
      _playPos = Duration.zero;
      _playDur = null;
    });
    await _audioPlayer.play(DeviceFileSource(path));
  }

  void _showImage(Entry entry) {
    if (entry.media == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FutureBuilder<String>(
        future: MediaStore().pathOf(entry.media!),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  tooltip: widget.model.tr('share'),
                  onPressed: () => _shareEntry(entry),
                ),
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  tooltip: widget.model.tr('download'),
                  onPressed: () async {
                    await _downloadEntry(entry);
                  },
                ),
              ],
            ),
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
    final result = await Navigator.push<Chat>(
      context,
      MaterialPageRoute(builder: (_) => ChatEditScreen(model: widget.model, chat: _chat)),
    );
    if (result == null) return;
    await widget.model.save();
    setState(() {});
  }

  // ignore: unused_element
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
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in widget.model.state.chats.where((c) => c.id == widget.chatId)) {
      c.deletedAt = now;
    }
    for (final r in widget.model.state.reminders.toList()) {
      if (r.chatId == widget.chatId) {
        await RemindersService.instance.cancel(r);
        widget.model.state.reminders.remove(r);
      }
    }
    await widget.model.save();
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleSelect(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _shareEntry(Entry e) async {
    try {
      await ShareService.shareEntry(e);
    } catch (_) {
      _toast(widget.model.tr('backup_error'), error: true);
    }
  }

  Future<void> _downloadEntry(Entry e) async {
    final path = await ShareService.downloadImage(e);
    if (!mounted) return;
    if (path != null) {
      _toast(widget.model.tr('downloaded'));
    } else {
      _toast(widget.model.tr('download_error'), error: true);
    }
  }

  Future<void> _shareSelected() async {
    final entries = widget.model.state.entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (entries.isEmpty) return;
    try {
      await ShareService.shareEntries(entries);
    } catch (_) {
      _toast(widget.model.tr('backup_error'), error: true);
    }
  }

  Future<void> _copySelected() async {
    final entries = widget.model.state.entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (entries.isEmpty) return;
    final texts = entries.map((e) {
      if (e.type == 'todo') {
        return (e.items ?? const <TodoItem>[]).map((i) => '${i.done ? '☑' : '☐'} ${i.text}').join('\n');
      }
      return e.text;
    }).where((t) => t.isNotEmpty).join('\n\n');
    if (texts.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: texts));
    _toast(widget.model.tr('copied'));
    setState(() => _selectedIds.clear());
  }

  Future<void> _forwardSelected() async {
    final entries = widget.model.state.entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (entries.isEmpty) return;
    final target = await showForwardDialog(context, widget.model);
    if (target == null) return;
    await _forwardEntries(entries, target);
  }

  Future<void> _deleteSelected() async {
    final entries = widget.model.state.entries.where((e) => _selectedIds.contains(e.id)).toList();
    if (entries.isEmpty) return;
    final ids = entries.map((e) => e.id).toSet();
    await UndoService.deleteEntries(widget.model, entries);
    _selectedIds.removeAll(ids);
    if (mounted) {
      setState(() {});
      _showUndoBar(entries);
    }
  }

  /// Telegram-style "Deleted · UNDO" pill with a 5-second countdown ring.
  void _showUndoBar(List<Entry> entries) {
    UndoToast.show(
      context,
      message: widget.model.tr('deleted'),
      actionLabel: widget.model.tr('undo'),
      p: p,
      onUndo: () => UndoService.restoreEntries(widget.model, entries),
    );
  }

  Future<void> _onCtxAction(Entry entry, EntryAction action) async {
    switch (action) {
      case EntryAction.schedTime:
        if (!mounted) return;
        final res = await showScheduleSheet(
          context,
          widget.model,
          initialDueAt: entry.dueAt,
          initialRecurrence: entry.recurrence,
          initialRecurrenceDays: entry.recurrenceDays,
          initialMonthDay: entry.monthDay,
        );
        if (res == null || res.dueAt == null) return;
        entry.dueAt = res.dueAt;
        entry.recurrence = res.recurrence;
        entry.recurrenceDays =
            res.recurrenceDays == null ? null : List.of(res.recurrenceDays!);
        entry.monthDay = res.monthDay;
        entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
        await widget.model.save();
        await widget.model.rescheduleAlarms();
        if (mounted) {
          setState(() {});
          _toast(widget.model.tr('change_time_done'));
        }
        break;
      case EntryAction.select:
        _toggleSelect(entry.id);
        HapticFeedback.selectionClick();
        break;
      case EntryAction.pin:
        entry.pinned = !entry.pinned;
        entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
        await widget.model.save();
        if (mounted) setState(() {});
        break;
      case EntryAction.share:
        await _shareEntry(entry);
        break;
      case EntryAction.download:
        await _downloadEntry(entry);
        break;
      case EntryAction.copy:
        final text = entry.type == 'todo'
            ? (entry.items ?? const <TodoItem>[])
                .map((i) => '${i.done ? '☑' : '☐'} ${i.text}')
                .join('\n')
            : entry.text;
        await Clipboard.setData(ClipboardData(text: text));
        _toast(widget.model.tr('copied'));
        break;
      case EntryAction.edit:
        if (entry.type == 'todo') {
          final items = await showTodoEditorDialog(context, widget.model, entry: entry);
          if (items == null) return;
          entry.items = items;
          entry.editedAt = DateTime.now().millisecondsSinceEpoch;
          entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
          await widget.model.save();
          if (mounted) setState(() {});
        } else {
          _editText.text = entry.text;
          setState(() => _editingId = entry.id);
        }
        break;
      case EntryAction.forward:
        final target = await showForwardDialog(context, widget.model);
        if (target == null || target.id == widget.chatId) return;
        await _forwardEntries([entry], target);
        break;
      case EntryAction.delete:
        final deleted = List<Entry>.of([entry]);
        await UndoService.deleteEntries(widget.model, [entry]);
        if (mounted) setState(() {});
        if (mounted) _showUndoBar(deleted);
        break;
    }
  }

  /// Forward with full field parity AND copy-on-forward media: the old
  /// copies silently dropped `monthDay`/`recurrenceDays` (breaking forwarded
  /// recurring tasks) and shared one media file between copies, so deleting
  /// either copy destroyed both.
  Future<void> _forwardEntries(List<Entry> list, Chat target) async {
    final store = MediaStore();
    for (final e in list) {
      final copy = e.copyForForward(target.id);
      if ((e.type == 'image' || e.type == 'audio' || e.type == 'video' || e.type == 'doc') &&
          e.media != null) {
        final newName = await store.copyMedia(e.media!);
        if (newName != null) {
          copy
            ..media = newName
            ..mediaName = e.type == 'image' ? newName : e.mediaName;
        }
      }
      widget.model.state.entries.add(copy);
    }
    await widget.model.save();
    if (mounted) {
      setState(() => _selectedIds.clear());
      _toast(widget.model.tr('forwarded_to', [target.name]));
    }
  }

  Future<void> _saveEdit(Entry entry) async {
    final text = _editText.text.trim();
    if (text.isEmpty) return;
    entry.text = text;
    entry.tags = extractTags(text);
    entry.editedAt = DateTime.now().millisecondsSinceEpoch;
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _editingId = null;
    _editText.clear();
    await widget.model.save();
    setState(() {});
  }

  String _timeWithEdited(Entry e) {
    // Defensive: if ts is 0 (legacy/corrupted entry), show nothing.
    if (e.ts == 0) return '';
    final base = fmtTime(e.ts);
    if (e.isEdited) return '$base · ${widget.model.tr('edited')}';
    return base;
  }

  /// Tappable timestamp under every message: opens the unified schedule
  /// sheet (date + time + repeat presets) — only in tasks chats.
  Widget _timeLabel(Entry e) {
    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Text(_timeWithEdited(e),
          style: TextStyle(fontSize: 10.5, color: p.textFaint)),
    );
    if (_chat.kind != 'tasks') return label;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _editEntrySchedule(e),
      child: label,
    );
  }

  Future<void> _editEntrySchedule(Entry entry) async {
    final res = await showScheduleSheet(
      context,
      widget.model,
      initialDueAt: entry.dueAt,
      initialRecurrence: entry.recurrence,
      initialRecurrenceDays: entry.recurrenceDays,
      initialMonthDay: entry.monthDay,
    );
    if (res == null || res.dueAt == null) return;
    entry.dueAt = res.dueAt;
    entry.recurrence = res.recurrence;
    entry.recurrenceDays =
        res.recurrenceDays == null ? null : List.of(res.recurrenceDays!);
    entry.monthDay = res.monthDay;
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await widget.model.save();
    await widget.model.rescheduleAlarms();
    if (mounted) {
      setState(() {});
      _toast(widget.model.tr('change_time_done'));
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 2500),
      backgroundColor: error ? const Color(0xFF3A2020) : p.bgChat,
    ));
  }

  // ---------------- pinned banner ----------------

  List<Entry> _pinnedEntries() =>
      widget.model.state.entries.where((e) => e.chatId == widget.chatId && e.pinned).toList()
        ..sort((a, b) => b.ts.compareTo(a.ts));

  Widget _buildPinnedBanner() {
    final pinned = _pinnedEntries();
    if (pinned.isEmpty) return const SizedBox.shrink();
    return Material(
      color: p.accent.withValues(alpha: .08),
      child: InkWell(
        onTap: () => _showPinnedSheet(pinned),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 16, color: p.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.model.tr('pinned_count', [pinned.length.toString()]),
                  style: TextStyle(fontSize: 13, color: p.accent, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: p.accent),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinnedSheet(List<Entry> pinned) {
    showModalBottomSheet(
      context: context,
      backgroundColor: p.bgChat,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: .4,
        minChildSize: .2,
        maxChildSize: .7,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: p.textFaint.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.push_pin, size: 18, color: p.accent),
                  const SizedBox(width: 8),
                  Text(
                    widget.model.tr('pinned_count', [pinned.length.toString()]),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.bubbleBorder),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: pinned.length,
                itemBuilder: (_, i) {
                  final e = pinned[i];
                  final preview = e.type == 'todo'
                      ? (e.items?.map((t) => t.text).join(', ') ?? '')
                      : e.text;
                  return ListTile(
                    leading: Icon(
                      e.type == 'todo' ? Icons.check_circle_outline : Icons.article_outlined,
                      size: 20,
                      color: p.textSoft,
                    ),
                    title: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.text),
                    ),
                    subtitle: Text(
                      _timeWithEdited(e),
                      style: TextStyle(fontSize: 11, color: p.textFaint),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.close, size: 18, color: p.textSoft),
                      onPressed: () async {
                        e.pinned = false;
                        e.updatedAt = DateTime.now().millisecondsSinceEpoch;
                        await widget.model.save();
                        if (mounted) setState(() {});
                        if (ctx.mounted) {
                          final remaining = _pinnedEntries();
                          if (remaining.isEmpty) {
                            Navigator.pop(ctx);
                          } else {
                            Navigator.pop(ctx);
                            _showPinnedSheet(remaining);
                          }
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _jumpToEntry(e.id);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _jumpToEntry(String entryId) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _bubbleContexts[entryId];
      if (ctx == null) return;
      await Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          alignment: .3);
      _highlightId = entryId;
      if (mounted) setState(() {});
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && _highlightId == entryId) setState(() => _highlightId = null);
    });
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final chat = _chatOrNull;

    // The chat can disappear while this screen is open (trash purge, sync).
    if (chat == null) {
      return Scaffold(
        backgroundColor: p.bg,
        body: Center(
          child: Text(model.tr('chat_deleted'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: p.textFaint)),
        ),
      );
    }

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) {
          setState(() => _selectedIds.clear());
        }
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopbar(chat),
                  _buildPinnedBanner(),
                  Expanded(child: _buildMessages(model)),
                  _buildComposer(),
                ],
              ),
              if (_recording) Positioned(left: 0, right: 0, bottom: 0, child: _buildRecordingPanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopbar(Chat chat) {
    if (_selecting) {
      final matches = widget.model.state.entries.where((e) => _selectedIds.contains(e.id)).toList();
      final one = matches.length == 1 ? matches.first : null;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        color: p.accent.withValues(alpha: .12),
        child: Row(
          children: [
            IconButton(icon: Icon(Icons.close, color: p.accent), onPressed: () => setState(() => _selectedIds.clear())),
            Text(widget.model.tr('selected', ['${_selectedIds.length}']), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.accent)),
            const Spacer(),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: p.accent),
              tooltip: 'menu',
              color: p.modalBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) async {
                if (v == 'time' && one != null) {
                  // Leave selection mode first — otherwise the checkboxes
                  // and highlight stay around the editor.
                  if (mounted) setState(() => _selectedIds.clear());
                  await _onCtxAction(one, EntryAction.schedTime);
                } else if (v == 'edit' && one != null) {
                  if (mounted) setState(() => _selectedIds.clear());
                  await _onCtxAction(one, EntryAction.edit);
                } else if (v == 'pin') {
                  for (final e in matches) {
                    e.pinned = !e.pinned;
                    e.updatedAt = DateTime.now().millisecondsSinceEpoch;
                  }
                  await widget.model.save();
                  if (mounted) setState(() => _selectedIds.clear());
                } else if (v == 'copy') {
                  await _copySelected();
                } else if (v == 'forward') {
                  await _forwardSelected();
                } else if (v == 'share') {
                  await _shareSelected();
                } else if (v == 'delete') {
                  await _deleteSelected();
                }
              },
              itemBuilder: (_) => [
                if (_chat.kind == 'tasks')
                  PopupMenuItem(
                      value: 'time',
                      enabled: one != null,
                      height: 42,
                      child: Row(children: [Icon(Icons.schedule_outlined, size: 18, color: one != null ? p.accent : p.textFaint), const SizedBox(width: 10), Text(widget.model.tr('change_time'), style: TextStyle(fontSize: 14, color: one != null ? p.text : p.textFaint))])),
                PopupMenuItem(
                    value: 'edit',
                    enabled: one != null && (one.type == 'text' || one.type == 'todo'),
                    height: 42,
                    child: Row(children: [Icon(Icons.edit, size: 18, color: one != null && (one.type == 'text' || one.type == 'todo') ? p.textSoft : p.textFaint), const SizedBox(width: 10), Text(widget.model.tr('edit'), style: TextStyle(fontSize: 14, color: one != null && (one.type == 'text' || one.type == 'todo') ? p.text : p.textFaint))])),
                PopupMenuItem(
                    value: 'pin',
                    height: 42,
                    child: Row(children: [Icon(Icons.push_pin_outlined, size: 18, color: p.accent), const SizedBox(width: 10), Text(widget.model.tr('pin'), style: TextStyle(fontSize: 14, color: p.text))])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'copy', height: 42, child: Row(children: [Icon(Icons.copy, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(widget.model.tr('copy'), style: TextStyle(fontSize: 14, color: p.text))])),
                PopupMenuItem(value: 'forward', height: 42, child: Row(children: [Icon(Icons.forward, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(widget.model.tr('forward'), style: TextStyle(fontSize: 14, color: p.text))])),
                PopupMenuItem(value: 'share', height: 42, child: Row(children: [Icon(Icons.share, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(widget.model.tr('share'), style: TextStyle(fontSize: 14, color: p.text))])),
                PopupMenuItem(value: 'delete', height: 42, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: p.danger), const SizedBox(width: 10), Text(widget.model.tr('delete'), style: TextStyle(fontSize: 14, color: p.danger))])),
              ],
            ),
          ],
        ),
      );
    }
    if (_searching) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        color: p.bgList,
        child: Row(
          children: [
            IconButton(icon: Icon(Icons.arrow_back, color: p.textSoft), onPressed: () => setState(() { _searching = false; _searchCtrl.clear(); _searchQuery = ''; })),
            Expanded(child: TextField(controller: _searchCtrl, autofocus: true, onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()), style: TextStyle(color: p.text, fontSize: 14), decoration: InputDecoration(hintText: widget.model.tr('search'), hintStyle: TextStyle(color: p.textFaint), border: InputBorder.none, isDense: true))),
            IconButton(icon: Icon(Icons.close, color: p.textSoft), onPressed: () => setState(() { _searching = false; _searchCtrl.clear(); _searchQuery = ''; })),
          ],
        ),
      );
    }
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
                case ChatTopAction.search:
                  setState(() => _searching = true);
                  break;
                case ChatTopAction.export:
                  await ShareService.exportChatMarkdown(
                      _chat.name, widget.model.state.entriesFor(widget.chatId));
                  break;
                case ChatTopAction.edit:
                  await _editChat();
                  break;
                case ChatTopAction.delete:
                  await _deleteChat();
                  break;
                case ChatTopAction.toggleHide:
                  _chat.tasksHideDone = !_chat.tasksHideDone;
                  await widget.model.save();
                  if (mounted) setState(() {});
                  break;
                case ChatTopAction.toggleNotifications:
                  _chat.notificationsEnabled = !_chat.notificationsEnabled;
                  await widget.model.save();
                  if (mounted) {
                    setState(() {});
                    _toast(_chat.notificationsEnabled
                        ? widget.model.tr('notifications_on')
                        : widget.model.tr('notifications_off'));
                  }
                  break;
                case ChatTopAction.remind:
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: ChatTopAction.search, child: Row(children: [Icon(Icons.search, size: 18, color: p.accent), const SizedBox(width: 10), Text(widget.model.tr('search_in_chat'), style: TextStyle(color: p.text))])),
              PopupMenuItem(value: ChatTopAction.export, child: Row(children: [Icon(Icons.ios_share, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(widget.model.tr('export_chat'), style: TextStyle(color: p.text))])),
              PopupMenuItem(
                  value: ChatTopAction.toggleNotifications,
                  child: Row(children: [
                    Icon(_chat.notificationsEnabled ? Icons.notifications : Icons.notifications_off, size: 18, color: p.textSoft),
                    const SizedBox(width: 10),
                    Text(_chat.notificationsEnabled ? widget.model.tr('notifications_on') : widget.model.tr('notifications_off'), style: TextStyle(color: p.text))
                  ])),
              if (_chat.kind == 'tasks')
                PopupMenuItem(
                    value: ChatTopAction.toggleHide,
                    child: Row(children: [
                      Icon(_chat.tasksHideDone ? Icons.visibility_off : Icons.visibility, size: 18, color: p.textSoft),
                      const SizedBox(width: 10),
                      Text(_chat.tasksHideDone ? widget.model.tr('show_done') : widget.model.tr('hide_done'), style: TextStyle(color: p.text))
                    ])),
              PopupMenuItem(value: ChatTopAction.edit, child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: p.textSoft), const SizedBox(width: 10), Text(widget.model.tr('edit_chat'), style: TextStyle(color: p.text))])),
              PopupMenuItem(value: ChatTopAction.delete, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: p.danger), const SizedBox(width: 10), Text(widget.model.tr('delete'), style: TextStyle(color: p.danger))])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(AppModel model) {
    var entries = sortedEntriesFor(model.state, widget.chatId);
    if (_chat.kind == 'tasks' && _chat.tasksHideDone) {
      entries = entries.where((e) {
        if (e.type != 'todo') return true;
        final items = e.items ?? const <TodoItem>[];
        if (items.isEmpty) return true;
        return items.any((i) => !i.done);
      }).toList();
    }
    if (_searching && _searchQuery.isNotEmpty) {
      final q = _searchQuery;
      entries = entries.where((e) => e.text.toLowerCase().contains(q) || e.tags.any((t) => t.toLowerCase().contains(q)) || (e.items?.any((i) => i.text.toLowerCase().contains(q)) ?? false)).toList();
    }
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

    Widget pill(String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: DayPill(label: label, p: p),
        );

    Widget makeRow(Entry e) {
      final highlight = _highlightId == e.id;
      final isSelected = _selectedIds.contains(e.id);
      final bubble = Builder(builder: (ctx) {
        _bubbleContexts[e.id] = ctx;
        return _buildBubble(model, e, highlight: highlight || isSelected, selected: isSelected);
      });
      Widget row = GestureDetector(
        onTap: _selecting ? () => _toggleSelect(e.id) : null,
        onLongPressStart: (d) {
          HapticFeedback.mediumImpact();
          _toggleSelect(e.id);
        },
        onSecondaryTapDown: (d) async {
          if (_selecting) {
            _toggleSelect(e.id);
          } else {
            final action = await showEntryCtxPopup(context, model, e, d.globalPosition, chatKind: _chat.kind);
            if (action != null) await _onCtxAction(e, action);
          }
        },
        child: bubble,
      );
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        color: isSelected ? p.accent.withValues(alpha: .08) : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: _selecting
                  ? Checkbox(
                      value: isSelected,
                      activeColor: p.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (_) => _toggleSelect(e.id),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(child: row),
          ],
        ),
      );
    }

    // Messenger mode, like Telegram: newest at bottom, view pinned to the bottom.
    // NOTE: sortedEntriesFor returns newest-first already.
    final children = <Widget>[];
    String? currentDay;
    for (final e in entries) {
      final day = fmtDay(e.ts, tr);
      if (currentDay != null && day != currentDay) {
        children.add(pill(currentDay!));
      }
      currentDay = day;
      children.add(makeRow(e));
    }
    if (currentDay != null) children.add(pill(currentDay!));

    // builder + reverse: index 0 renders at the BOTTOM, and children[0] is
    // the NEWEST row (entries iterate newest-first) — plain children[i] puts
    // old messages on top and fresh ones arriving from the bottom edge.
    // Lazy building keeps long chats from materializing every row at once.
    return ListView.builder(
      controller: _listCtrl,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: children.length,
      itemBuilder: (ctx, i) => children[i],
    );
  }

  Widget _buildBubble(AppModel model, Entry entry, {required bool highlight, bool selected = false}) {
    final Widget content = switch (entry.type) {
      'text' => _buildTextBubble(model, entry),
      'image' => _buildImageBubble(model, entry),
      'audio' => _buildAudioBubble(model, entry),
      'video' => _buildVideoBubble(model, entry),
      'todo' => _buildTodoBubble(model, entry),
      'doc' => _buildDocBubble(model, entry),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          if (entry.pinned)
            Positioned(
              top: -4,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: p.bgChat,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.push_pin, size: 12, color: p.accent),
              ),
            ),
        ],
      ),
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

    final isMd = _isMarkdown(entry.text);
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
            child: isMd
                ? MarkdownBody(
                    data: entry.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(fontSize: 14.5, color: p.text, height: 1.35),
                      strong: TextStyle(fontWeight: FontWeight.w700, color: p.text),
                      em: TextStyle(fontStyle: FontStyle.italic, color: p.text),
                      code: TextStyle(fontFamily: 'monospace', fontSize: 13, color: p.text, backgroundColor: p.bgChat),
                      blockquote: TextStyle(color: p.textSoft, fontStyle: FontStyle.italic),
                      tableHead: TextStyle(fontWeight: FontWeight.w700, color: p.text),
                      tableBody: TextStyle(color: p.text),
                      checkbox: TextStyle(color: p.accent),
                    ),
                    onTapLink: (text, href, title) {
                      if (href != null && href.isNotEmpty) {
                        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                      }
                    },
                  )
                : SelectableText.rich(
                    TextSpan(children: _highlightTags(entry.text, p)),
                    style: TextStyle(fontSize: 14.5, color: p.text, height: 1.35),
                  ),
          ),
          // Link preview card: fetch OG metadata for the first URL in the text.
          if (!isMd) ..._maybeLinkPreview(entry.text),
          if (entry.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [for (final t in entry.tags) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: p.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)), child: Text('#$t', style: TextStyle(fontSize: 11, color: p.accent, fontWeight: FontWeight.w600)))],
              ),
            ),
          _timeLabel(entry),
        ],
      ),
    );
  }

  bool _isMarkdown(String t) {
    if (t.contains('```')) return true;
    if (t.contains('|') && t.contains('\n')) return true;
    if (RegExp(r'(^|\n)#{1,6}\s').hasMatch(t)) return true;
    if (RegExp(r'\*\*[^*]+\*\*').hasMatch(t)) return true;
    if (RegExp(r'__[^_]+__').hasMatch(t)) return true;
    if (RegExp(r'^\s*[-*]\s+\[.\].*', multiLine: true).hasMatch(t)) return true;
    if (RegExp(r'^\s*[-*]\s+').hasMatch(t)) return true;
    if (RegExp(r'^\s*\d+\.\s+').hasMatch(t)) return true;
    if (t.contains('](')) return true;
    return false;
  }

  List<TextSpan> _highlightTags(String text, Palette p) {
    // Dispose recognizers from the previous build to prevent native resource leak.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = <TextSpan>[];
    // Combined regex: #tag OR https URL.
    final re = RegExp(r'(#[\wа-яёіїєґА-ЯЁІЇЄҐ]+|https?://[^\s<>")\]]+)');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final match = m.group(0)!;
      if (match.startsWith('#')) {
        spans.add(TextSpan(
          text: match,
          style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
        ));
      } else {
        // URL: styled as a link and wrapped with tap gesture. Recognizers
        // are tracked and disposed with the State — a fresh one per build
        // used to leak native resources on every rebuild.
        final recognizer = _linkTapRecognizer(match);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: match,
          style: TextStyle(color: Colors.blue[400], decoration: TextDecoration.underline, fontSize: 14.5, height: 1.35),
          recognizer: recognizer,
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  GestureRecognizer _linkTapRecognizer(String url) {
    return TapGestureRecognizer()..onTap = () {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    };
  }

  /// If [text] contains a URL, return a widget list with a compact preview
  /// card; otherwise an empty list (used with the spread operator `...`).
  List<Widget> _maybeLinkPreview(String text) {
    final m = RegExp(r'https?://[^\s<>")\]]+').firstMatch(text);
    if (m == null) return const [];
    final url = m.group(0)!;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: FutureBuilder<LinkPreviewData?>(
          future: _previewFor(url),
          builder: (ctx, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final d = snap.data!;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                decoration: BoxDecoration(
                  color: p.bgChat,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.bubbleBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (d.imageUrl != null)
                    SizedBox(
                      width: double.infinity, height: 100,
                      child: Image.network(d.imageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.domain, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.textFaint)),
                      const SizedBox(height: 2),
                      Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                      if (d.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(d.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.textSoft)),
                      ],
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildImageBubble(AppModel model, Entry entry) {
    if (entry.media == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _showImage(entry),
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: p.bubbleOwn,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<String>(
                future: _pathOf(entry.media!),
                builder: (ctx, snap) => snap.hasData
                    ? SizedBox(
                        width: 260,
                        height: 300,
                        // Decode at display resolution, not file size — a
                        // 12 MP quickCopy used to allocate a full bitmap.
                        child: Image.file(File(snap.data!),
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            cacheWidth: (260 * MediaQuery.devicePixelRatioOf(context)).round()),
                      )
                    : Container(width: 260, height: 300, color: p.bgChat),
            ),
            if (entry.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                child: Text(entry.text, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.35)),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: _timeLabel(entry),
              ),
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
                : '${entry.duration ?? 0} ${model.tr('sec')} ·',
            style: TextStyle(fontSize: 11, color: p.textFaint),
          ),
          if (!playing) _timeLabel(entry),
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
          Row(mainAxisSize: MainAxisSize.min, children: [
            if ((entry.mediaSize ?? '').isNotEmpty)
              Text('${entry.mediaSize ?? ''} ·',
                  style: TextStyle(fontSize: 11, color: p.textFaint)),
            _timeLabel(entry),
          ]),
        ],
      ),
    );
  }

  Widget _buildTodoBubble(AppModel model, Entry entry) {
    final allItems = entry.items ?? const <TodoItem>[];
    final overdue = entry.dueAt != null &&
        entry.dueAt! < DateTime.now().millisecondsSinceEpoch &&
        allItems.any((i) => !i.done);
    final doneCount = allItems.where((i) => i.done).length;
    final progress = allItems.isEmpty ? 0.0 : doneCount / allItems.length;
    final rows = _todoRows(model, entry, allItems);
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 7),
      decoration: BoxDecoration(
        color: p.bubbleOwn,
        border: Border.all(color: overdue ? p.danger.withValues(alpha: .5) : p.bubbleBorder),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (entry.dueAt != null)
            GestureDetector(
              onTap: () => _editEntrySchedule(entry),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: overdue ? p.danger.withValues(alpha: .12) : p.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.schedule, size: 13, color: overdue ? p.danger : p.accent),
                  const SizedBox(width: 4),
                  Text(_fmtDue(entry.dueAt!, model.tr), style: TextStyle(fontSize: 11, color: overdue ? p.danger : p.accent, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          if (allItems.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: p.divider,
                      valueColor: AlwaysStoppedAnimation(p.accent),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$doneCount/${allItems.length}',
                    style: TextStyle(fontSize: 10.5, color: p.textFaint, fontWeight: FontWeight.w600)),
              ]),
            ),
          if (rows.isEmpty && allItems.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(model.tr('todo_all_done'), style: TextStyle(fontSize: 13, color: p.textFaint, fontStyle: FontStyle.italic))),
          ...rows,
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showTaskItemSheet(model, entry),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 15, color: p.accent),
                  const SizedBox(width: 3),
                  Text(model.tr('todo_add'), style: TextStyle(fontSize: 11.5, color: p.accent, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
          _timeLabel(entry),
        ],
      ),
    );
  }

  List<Widget> _todoRows(AppModel model, Entry entry, List<TodoItem> allItems) {
    final hideDone = _chat.kind == 'tasks' && _chat.tasksHideDone;
    final byParent = <String?, List<TodoItem>>{};
    for (final it in allItems) {
      byParent.putIfAbsent(it.parentId, () => []).add(it);
    }

    bool hidden(TodoItem t) {
      if (!hideDone || !t.done) return false;
      return (byParent[t.id] ?? const <TodoItem>[]).every(hidden);
    }

    final rows = <Widget>[];
    void walk(String? parent, int depth) {
      for (final it in byParent[parent] ?? const <TodoItem>[]) {
        if (hidden(it)) continue;
        rows.add(_todoRow(model, entry, it, depth));
        walk(it.id, depth + 1);
      }
    }

    walk(null, 0);
    return rows;
  }

  Widget _todoRow(AppModel model, Entry entry, TodoItem item, int depth) {
    final isSub = depth > 0;
    return Padding(
      padding: EdgeInsets.only(left: depth * 22.0, bottom: isSub ? 0 : 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.priority > 0 && !isSub)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 4),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: item.done ? p.textFaint.withValues(alpha: .4) : p.priority(item.priority),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _toggleTodoItem(model, entry, item),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: isSub ? 17 : 20,
                height: isSub ? 17 : 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.done ? p.accent : Colors.transparent,
                  border: Border.all(color: item.done ? p.accent : p.textFaint.withValues(alpha: .55), width: 2),
                ),
                child: item.done ? Icon(Icons.check, size: 12, color: Colors.white) : null,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _showTaskItemSheet(model, entry, item: item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.5),
                child: Text(
                  item.text,
                  style: TextStyle(
                    fontSize: isSub ? 12.5 : 13.5,
                    color: item.done ? p.textFaint : p.text,
                    decoration: item.done ? TextDecoration.lineThrough : null,
                    decorationColor: p.textFaint,
                  ),
                ),
              ),
            ),
          ),
          if (!isSub)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _showTaskItemSheet(model, entry, parentId: item.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
                child: Icon(Icons.subdirectory_arrow_right, size: 14, color: p.textFaint),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleTodoItem(AppModel model, Entry entry, TodoItem item) async {
    toggleTodoCascade(entry.items ??= <TodoItem>[], item.id);
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await model.save();
    if (item.done) unawaited(Sounds.taskDone());
    // Completing an OVERDUE recurring task snaps its deadline forward so
    // the checkmark sticks until the new period ends (otherwise rollover
    // would instantly uncheck it).
    final snapped = entry.recurrence != null && snapCompletedRecurring(entry, DateTime.now());
    final rolled = model.rolloverRecurring();
    if (snapped || rolled > 0) {
      await model.save();
      await _scheduleEntryReminder(entry);
    }
    if (mounted) setState(() {});
  }

  /// Bottom sheet for creating / renaming / deleting a single task item.
  /// [parentId] starts a new subtask under that parent.
  Future<void> _showTaskItemSheet(AppModel model, Entry entry, {TodoItem? item, String? parentId}) async {
    final ctrl = TextEditingController(text: item?.text ?? '');
    var priority = item?.priority ?? 0;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.modalBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) => SafeArea(
        top: false,
        child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item != null ? model.tr('edit') : model.tr('todo_add'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(color: p.text, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: p.bgChat,
                hintText: model.tr('todo_item_hint'),
                hintStyle: TextStyle(color: p.textFaint, fontSize: 13.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, 'save'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text(model.tr('priority'), style: TextStyle(fontSize: 12, color: p.textSoft, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              for (final pr in [0, 1, 2])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    selected: priority == pr,
                    onSelected: (_) => setSheetState(() => priority = pr),
                    label: Text(model.tr('priority_$pr'), style: TextStyle(fontSize: 12, color: priority == pr ? Colors.white : p.text)),
                    selectedColor: p.priority(pr),
                    backgroundColor: p.bgChat,
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (item != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  icon: Icon(Icons.delete_outline, size: 18, color: p.danger),
                  label: Text(model.tr('delete'), style: TextStyle(color: p.danger, fontSize: 13)),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(model.tr('cancel'), style: TextStyle(color: p.textSoft))),
              const SizedBox(width: 8),
               FilledButton(
                 style: FilledButton.styleFrom(backgroundColor: p.accent),
                 onPressed: () => Navigator.pop(ctx, 'save'),
                 child: Text(model.tr('save')),
               ),
             ]),
          ],
        ),
      ),
      )),
    );
    if (action == null) return;
    final items = entry.items ?? <TodoItem>[];
    if (action == 'delete') {
      removeTodoItem(items, item!.id);
    } else if (action == 'save') {
      final text = ctrl.text.trim();
      if (text.isEmpty) return;
      if (item != null) {
        item.text = text;
        item.priority = priority;
      } else {
        items.insert(_insertAfterSubtree(items, parentId), TodoItem(id: uid('t'), text: text, parentId: parentId, priority: priority));
      }
    }
    await model.save();
    if (mounted) setState(() {});
  }

  /// Index right after the last descendant of [parentId] — keeps a newly
  /// added subtask visually grouped with its parent in list order.
  int _insertAfterSubtree(List<TodoItem> items, String? parentId) {
    if (parentId == null) return items.length;
    var idx = items.indexWhere((i) => i.id == parentId);
    if (idx < 0) return items.length;
    final ids = {parentId};
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = idx + 1; i < items.length; i++) {
        if (ids.contains(items[i].parentId)) {
          ids.add(items[i].id);
          idx = i;
          changed = true;
        }
      }
    }
    return idx + 1;
  }

  // -- doc bubble & viewer ------------------------------------------------

  static IconData _fileIcon(String? name) {
    final ext = (name?.split('.').last ?? '').toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf,
      'txt' || 'log' || 'csv' => Icons.description,
      'doc' || 'docx' => Icons.article,
      'xls' || 'xlsx' || 'csv' => Icons.table_chart,
      'ppt' || 'pptx' => Icons.slideshow,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip,
      'json' || 'xml' || 'html' || 'htm' => Icons.code,
      'md' => Icons.smart_toy_outlined,
      _ => Icons.insert_drive_file,
    };
  }

  /// Whether the file extension is one we can display as readable text.
  static bool _isTextFile(String? name) {
    final ext = (name?.split('.').last ?? '').toLowerCase();
    return const {'txt', 'log', 'csv', 'json', 'xml', 'html', 'htm', 'md', 'yaml', 'yml', 'ini', 'cfg', 'conf', 'sh', 'dart', 'py', 'js', 'ts', 'css'}.contains(ext);
  }

  Widget _buildDocBubble(AppModel model, Entry entry) {
    final ext = (entry.mediaName?.split('.').last ?? '').toUpperCase();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showDocument(entry),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.bubbleOwn,
          border: Border.all(color: p.bubbleBorder),
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14), topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14), bottomRight: Radius.circular(3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: p.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
              child: Icon(_fileIcon(entry.mediaName), color: p.accent, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.mediaName ?? entry.media ?? 'file',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text('${ext.isNotEmpty ? '$ext · ' : ''}${entry.mediaSize ?? ''}',
                  style: TextStyle(fontSize: 11.5, color: p.textFaint)),
            ])),
          ]),
          if (entry.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(entry.text, maxLines: 6, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: p.textSoft, height: 1.4)),
          ],
          const SizedBox(height: 4),
          _timeLabel(entry),
        ]),
      ),
    );
  }

  Future<void> _showDocument(Entry entry) async {
    if (entry.media == null) return;
    final path = await MediaStore().pathOf(entry.media!);
    if (!mounted) return;

    // Text-readable files: show content in-app.
    if (_isTextFile(entry.mediaName) && await File(path).exists()) {
      try {
        final content = await File(path).readAsString();
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(
              backgroundColor: p.bg,
              iconTheme: IconThemeData(color: p.text),
              title: Text(entry.mediaName ?? 'file',
                  style: TextStyle(color: p.text, fontSize: 15)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: widget.model.tr('share'),
                  onPressed: () => _shareEntry(entry),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(content,
                  style: TextStyle(fontSize: 13.5, color: p.text, fontFamily: 'monospace', height: 1.5)),
            ),
          ),
        ));
        return;
      } catch (_) {}
    }

    // Everything else: open with system handler.
    try {
      await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _toast(widget.model.tr('cant_open_file'));
    }
  }

  Widget _buildComposer() {
    final model = widget.model;
    if (_chat.kind == 'rss') {
      return Container(
        padding: const EdgeInsets.all(12),
        color: p.bgList,
        child: Row(
          children: [
            Icon(Icons.rss_feed, color: p.textFaint, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(model.tr('rss_only_channel'), style: TextStyle(color: p.textFaint, fontSize: 13))),
            TextButton(onPressed: () async { await RssService.fetchForChat(_chat, model.state); if (mounted) setState(() {}); }, child: Text(model.tr('rss_refresh'), style: TextStyle(color: p.accent))),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      color: p.bgList,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImagePath != null) _buildPendingImageBar(model),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.attach_file, color: p.textSoft),
                tooltip: model.tr('attach'),
                onPressed: () => _showAttachSheet(model),
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
                style: TextStyle(color: p.text, fontSize: 14.5),
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: _pendingImagePath != null ? model.tr('caption_hint') : model.tr('message_hint'),
                  hintStyle: TextStyle(color: p.textFaint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) {
              final hasSomething = _text.text.trim().isNotEmpty || _pendingImagePath != null;
              return hasSomething
                  ? GestureDetector(
                      onLongPressStart: _chat.kind == 'tasks'
                          ? (d) => _sendTextWithDate()
                          : null,
                      child: IconButton.filled(
                        icon: const Icon(Icons.send, color: Colors.white),
                        style: IconButton.styleFrom(backgroundColor: p.accent),
                        onPressed: _submitComposer,
                      ),
                    )
                  : GestureDetector(
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
                    );
            },
          ),
        ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingImageBar(AppModel model) {
    return Container(
      margin: const EdgeInsets.fromLTRB(46, 4, 4, 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: p.bgChat, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(_pendingImagePath!), width: 52, height: 52, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(model.tr('photo'), style: TextStyle(fontSize: 13.5, color: p.textSoft)),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: p.textFaint),
            tooltip: model.tr('cancel'),
            onPressed: () => setState(() => _pendingImagePath = null),
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