import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

const _kofiUrl = 'https://ko-fi.com/k_k';
const _firstLaunchKey = 'tn-first-launch';
const _dismissedKey = 'tn-support-banner-dismissed';
const _dismissedTimeKey = 'tn-support-banner-dismissed-time';

/// Call once on app start to ensure first launch timestamp exists.
Future<void> ensureFirstLaunch() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_firstLaunchKey)) {
      await prefs.setInt(_firstLaunchKey, DateTime.now().millisecondsSinceEpoch);
    }
  } catch (_) {}
}

/// True when banner should be shown: 14 days passed, not dismissed (or dismissed >90 days ago).
Future<bool> shouldShowSupportBanner() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final first = prefs.getInt(_firstLaunchKey);
    if (first == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    const twoWeeks = 14 * 24 * 3600 * 1000;
    if (now - first < twoWeeks) return false;
    final dismissed = prefs.getBool(_dismissedKey) ?? false;
    if (!dismissed) return true;
    // If dismissed, allow to show again after 90 days (soft reminder, not spam)
    final dismissedAt = prefs.getInt(_dismissedTimeKey) ?? 0;
    const ninetyDays = 90 * 24 * 3600 * 1000;
    if (dismissedAt != 0 && now - dismissedAt > ninetyDays) return true;
    return false;
  } catch (_) {
    return false;
  }
}

Future<void> dismissSupportBanner() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
    await prefs.setInt(_dismissedTimeKey, DateTime.now().millisecondsSinceEpoch);
  } catch (_) {}
}

class SupportBanner extends StatelessWidget {
  const SupportBanner({super.key, required this.p, required this.tr, this.onDismiss});

  final Palette p;
  final String Function(String, [List<String>?]) tr;
  final VoidCallback? onDismiss;

  Future<void> _openKofi() async {
    try {
      await launchUrl(Uri.parse(_kofiUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accent.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openKofi,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                child: const Center(child: Text('❤', style: TextStyle(fontSize: 16, color: Colors.white))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('support_banner_title'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
                    const SizedBox(height: 2),
                    Text(tr('support_banner_text'),
                        style: TextStyle(fontSize: 11.5, color: p.textSoft, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: p.textFaint),
                tooltip: tr('close'),
                onPressed: () async {
                  await dismissSupportBanner();
                  onDismiss?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
