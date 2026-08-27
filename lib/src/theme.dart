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

const lightPalette = Palette(
  name: 'light',
  accent: Color(0xFF2AABEE),
  accentDk: Color(0xFF1E96D6),
  bg: Color(0xFFFFFFFF),
  bgList: Color(0xFFFFFFFF),
  bgChat: Color(0xFFEDF2F5),
  bubbleOwn: Color(0xFFE4F3FF),
  bubbleBorder: Color(0xFFD3EAFB),
  text: Color(0xFF0F1721),
  textSoft: Color(0xFF7C8A97),
  textFaint: Color(0xFFA9B4BE),
  divider: Color(0xFFE6E9EC),
  danger: Color(0xFFE05353),
  rowActive: Color(0xFFF5F7F9),
  modalBg: Color(0xFFFFFFFF),
  priLow: Color(0xFF4CAF50),
  priMed: Color(0xFFF5A623),
  priHigh: Color(0xFFE24A4A),
);

const darkPalette = Palette(
  name: 'dark',
  accent: Color(0xFF4EA4F6),
  accentDk: Color(0xFF71B8F8),
  bg: Color(0xFF1C232C),
  bgList: Color(0xFF1C232C),
  bgChat: Color(0xFF262E39),
  bubbleOwn: Color(0xFF2F4A63),
  bubbleBorder: Color(0xFF3A5772),
  text: Color(0xFFEDF1F5),
  textSoft: Color(0xFFA2ACB6),
  textFaint: Color(0xFF717B85),
  divider: Color(0xFF323B46),
  danger: Color(0xFFF07575),
  rowActive: Color(0xFF28313C),
  modalBg: Color(0xFF262E39),
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