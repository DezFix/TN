import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Telegram-style floating notification banner dropped from the top of the
/// screen. Used by ReminderEngine when the app window is focused — the
/// system toast would be invisible behind our own window anyway.
void showInAppBanner(
  BuildContext context,
  Palette p, {
  required String title,
  required String body,
  VoidCallback? onTap,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _BannerView(
      remove: () {
        try {
          entry.remove();
        } catch (_) {}
      },
      p: p,
      title: title,
      body: body,
      onTap: onTap,
    ),
  );
  overlay.insert(entry);
}

class _BannerView extends StatefulWidget {
  const _BannerView({
    required this.remove,
    required this.p,
    required this.title,
    required this.body,
    this.onTap,
  });

  final VoidCallback remove;
  final Palette p;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _auto = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    _auto?.cancel();
    await _c.reverse();
    widget.remove();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(anim),
        child: FadeTransition(
          opacity: anim,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                widget.onTap?.call();
                _dismiss();
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: widget.p.bgChat.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: widget.p.bubbleBorder),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: widget.p.accent.withValues(alpha: .16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.notifications_active, size: 17, color: widget.p.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: widget.p.text)),
                          if (widget.body.isNotEmpty)
                            Text(widget.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: widget.p.textSoft)),
                        ],
                      ),
                    ),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close, size: 16, color: widget.p.textFaint),
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
