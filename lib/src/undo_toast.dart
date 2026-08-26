import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// In-app "Deleted · UNDO" toast, Telegram-style: a rounded pill docked to
/// the bottom with a circular countdown ring. Auto-dismisses when the ring
/// empties ([duration]); tapping anywhere on it fires [onUndo] once and
/// closes immediately. Replaces the old Material SnackBar that could hang
/// on screen indefinitely.
class UndoToast {
  static OverlayEntry? _entry;
  static Timer? _autoTimer;

  static void show(
    BuildContext context, {
    required String message,
    required String actionLabel,
    required VoidCallback onUndo,
    required Palette p,
    Duration duration = const Duration(seconds: 5),
  }) {
    dismiss();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    var undone = false;
    entry = OverlayEntry(
      builder: (_) => _UndoToastView(
        message: message,
        actionLabel: actionLabel,
        palette: p,
        duration: duration,
        onUndo: () {
          if (undone) return;
          undone = true;
          _close();
          onUndo();
        },
        onExpired: _close,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void _close() {
    _autoTimer?.cancel();
    _autoTimer = null;
    try {
      _entry?.remove();
    } catch (_) {}
    _entry = null;
  }

  static void dismiss() => _close();
}

class _UndoToastView extends StatefulWidget {
  const _UndoToastView({
    required this.message,
    required this.actionLabel,
    required this.palette,
    required this.duration,
    required this.onUndo,
    required this.onExpired,
  });

  final String message;
  final String actionLabel;
  final Palette palette;
  final Duration duration;
  final VoidCallback onUndo;
  final VoidCallback onExpired;

  @override
  State<_UndoToastView> createState() => _UndoToastViewState();
}

class _UndoToastViewState extends State<_UndoToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240));
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: widget.duration, value: 0);
  Timer? _expireTimer;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _ring.forward();
    // Fire slightly after the ring completes so the empty circle is visible
    // for a beat before the pill slides away.
    _expireTimer =
        Timer(widget.duration + const Duration(milliseconds: 250), () {
      _slide.reverse().then((_) => widget.onExpired());
    });
  }

  @override
  void dispose() {
    _expireTimer?.cancel();
    _slide.dispose();
    _ring.dispose();
    super.dispose();
  }

  Future<void> _undo() async {
    await _slide.reverse();
    widget.onUndo();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 14,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1.6), end: Offset.zero)
            .animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _slide, curve: Curves.easeOut),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _undo,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: p.bgChat,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.bubbleBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: p.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: p.text)),
                    ),
                    const SizedBox(width: 10),
                    Text(widget.actionLabel,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.accent)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: AnimatedBuilder(
                        animation: _ring,
                        builder: (_, __) => CustomPaint(
                          painter: _CountdownRingPainter(
                            progress: 1 - _ring.value,
                            color: p.accent,
                            track: p.divider,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  /// 1.0 at the start of the window → 0.0 when time is up.
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1.5;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -3.14159 / 2, 6.28318 * progress.clamp(0.0, 1.0), false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
