import 'dart:async';

import 'package:flutter/material.dart';

/// Telegram-style desktop toast that slides in from the bottom-right corner.
/// Used on Windows instead of the system tray notification.
class WinToast {
  static OverlayEntry? _entry;
  static Timer? _dismissTimer;

  static void show({
    required BuildContext context,
    required String title,
    required String body,
    VoidCallback? onTap,
    List<(String, String)> actions = const [],
    void Function(String actionKey)? onAction,
  }) {
    dismiss();
    _dismissTimer = Timer(const Duration(seconds: 8), dismiss);

    _entry = OverlayEntry(builder: (_) => _ToastWidget(
      title: title,
      body: body,
      onTap: onTap,
      onDismiss: dismiss,
      actions: actions,
      onAction: (key) {
        dismiss();
        onAction?.call(key);
      },
    ));
    Overlay.of(context).insert(_entry!);
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    try {
      _entry?.remove();
    } catch (_) {}
    _entry = null;
  }
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.title,
    required this.body,
    this.onTap,
    this.onDismiss,
    this.actions = const [],
    this.onAction,
  });
  final String title;
  final String body;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final List<(String, String)> actions;
  final void Function(String actionKey)? onAction;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: () {
              widget.onTap?.call();
              widget.onDismiss?.call();
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 360,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF17212B),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8A9BA8),
                      ),
                    ),
                    if (widget.actions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (final (key, label) in widget.actions) ...[
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => widget.onAction?.call(key),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                child: Text(label,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2AABEE))),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ],
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
