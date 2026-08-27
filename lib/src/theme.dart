import 'package:flutter/material.dart';

class Palette {
  const Palette({
    required this.name,
    required this.accent,
    required this.accentDk,
    required this.bg,
    required this.bgList,
    required this.bgChat,
    required this.bubbleOwn,
    required this.bubbleBorder,
    required this.text,
    required this.textSoft,
    required this.textFaint,
    required this.divider,
    required this.danger,
    required this.rowActive,
    required this.modalBg,
    required this.priLow,
    required this.priMed,
    required this.priHigh,
  });

  final String name;
  final Color accent;
  final Color accentDk;
  final Color bg;
  final Color bgList;
  final Color bgChat;
  final Color bubbleOwn;
  final Color bubbleBorder;
  final Color text;
  final Color textSoft;
  final Color textFaint;
  final Color divider;
  final Color danger;
  final Color rowActive;
  final Color modalBg;
  final Color priLow;
  final Color priMed;
  final Color priHigh;

  /// Color for the given task priority profile (0 = normal, 1 = medium, 2 = high).
  Color priority(int p) => switch (p) {
        1 => priMed,
        2 => priHigh,
        _ => priLow,
      };
}

// ── TN Design System ──────────────────────────────────────────────────
// Unified ecosystem tokens: spacing, radii, motion, typography.
// Keep Palette thin — tokens live here so every screen uses one source.

abstract class TNRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
  static const double bubble = 14;
  static const double sheet = 18;
}

abstract class TNSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract class TNDuration {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
}

abstract class TNTypography {
  // Single source of truth — every screen must use these.
  static const sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );
  static const chatTitle = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.2);
  static const chatPreview = TextStyle(fontSize: 13.5, height: 1.35);
  static const time = TextStyle(fontSize: 11, height: 1);
  static const bubbleText = TextStyle(fontSize: 14.5, height: 1.35);
}

const lightPalette = Palette(
  name: 'light',
  accent: Color(0xFF2AABEE),
  accentDk: Color(0xFF1E96D6),
  bg: Color(0xFFF8FAFB),
  bgList: Color(0xFFF8FAFB),
  bgChat: Color(0xFFEAF0F4),
  bubbleOwn: Color(0xFFE4F3FF),
  bubbleBorder: Color(0xFFD3EAFB),
  text: Color(0xFF0F1721),
  textSoft: Color(0xFF6E7F8F),
  textFaint: Color(0xFF7A8A9A),
  divider: Color(0xFFE2E7EB),
  danger: Color(0xFFE05353),
  rowActive: Color(0xFFEEF2F5),
  modalBg: Color(0xFFFFFFFF),
  priLow: Color(0xFF4CAF50),
  priMed: Color(0xFFF5A623),
  priHigh: Color(0xFFE24A4A),
);

const darkPalette = Palette(
  name: 'dark',
  accent: Color(0xFF4EA4F6),
  accentDk: Color(0xFF71B8F8),
  bg: Color(0xFF151B22),
  bgList: Color(0xFF151B22),
  bgChat: Color(0xFF222C37),
  bubbleOwn: Color(0xFF2B445C),
  bubbleBorder: Color(0xFF354F68),
  text: Color(0xFFEDF1F5),
  textSoft: Color(0xFF9AA8B6),
  textFaint: Color(0xFF7B8693),
  divider: Color(0xFF2E3845),
  danger: Color(0xFFF07575),
  rowActive: Color(0xFF252F3B),
  modalBg: Color(0xFF222C37),
  priLow: Color(0xFF6BCE6F),
  priMed: Color(0xFFF0B429),
  priHigh: Color(0xFFF07575),
);

Palette paletteFor(String theme) => theme == 'dark' ? darkPalette : lightPalette;

Color colorFromHex(String hex) {
  var value = hex.replaceAll('#', '');
  if (value.length == 6) value = 'FF$value';
  return Color(int.parse('0x$value'));
}

/// Shared helpers so every screen uses one radius / shadow / card spec.
extension PaletteX on Palette {
  bool get isDark => name == 'dark';
  Color get surfaceVariant => bgChat;
  Color get outline => divider;
  Color get onAccent => Colors.white;
  // Subtle card shadow — light only; dark uses border only.
  List<BoxShadow> get cardShadow => isDark
      ? const []
      : [
          BoxShadow(
            color: Color(0x0D0F1721),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ];
}

Widget tnSectionLabel(String text, Palette p, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: TNTypography.sectionLabel.copyWith(color: p.textFaint)),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );

Widget tnCard(Palette p, {required Widget child, EdgeInsets? padding, VoidCallback? onTap}) {
  final card = Container(
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: p.bgChat,
      borderRadius: BorderRadius.circular(TNRadii.md),
      border: Border.all(color: p.divider.withValues(alpha: p.isDark ? 0.5 : 0.35)),
      boxShadow: p.cardShadow,
    ),
    child: child,
  );
  if (onTap == null) return card;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(TNRadii.md),
      onTap: onTap,
      child: card,
    ),
  );
}

Widget tnEmptyState({
  required Palette p,
  required IconData icon,
  required String title,
  String? subtitle,
  String? actionLabel,
  VoidCallback? onAction,
}) =>
    Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: p.accent),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text, height: 1.3)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TNRadii.md)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 18, color: Colors.white),
                label: Text(actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );