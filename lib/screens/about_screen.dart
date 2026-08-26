import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../src/app_model.dart';
import '../src/app_update.dart';
import '../src/theme.dart';

/// "About": version + tagline, changelog viewer, manual update check and
/// the ko-fi support link.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _checking = false;
  bool _loadingChangelog = false;

  String tr(String key, [List<String>? args]) => widget.model.tr(key, args);
  Palette get p => widget.model.p;

  void _toast(String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: p.bgChat));
  }

  Future<void> _openKofi() async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse('https://ko-fi.com/k_k'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) _toast('ko-fi.com/k_k • ${tr('support')}');
  }

  /// Renders the latest GitHub release body as a markdown sheet; falls back
  /// to opening the releases page offline.
  Future<void> _openChangelog() async {
    if (_loadingChangelog) return;
    setState(() => _loadingChangelog = true);
    final rel = await fetchLatestRelease();
    if (!mounted) return;
    setState(() => _loadingChangelog = false);
    if (rel == null) {
      _toast(tr('update_check_failed'));
      try {
        await launchUrl(Uri.parse(repoPageUrl),
            mode: LaunchMode.externalApplication);
      } catch (_) {}
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.modalBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .95,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: p.divider, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(rel.name.isNotEmpty ? rel.name : 'TN ${rel.tag}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
            ),
            Expanded(child: releaseMarkdown(rel.body, p, controller: scrollCtrl)),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    await manualCheckForUpdate(context, widget.model);
    if (!mounted) return;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title,
        {VoidCallback? onTap, Widget? trailing, Color? iconColor}) {
      return ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, size: 20, color: iconColor ?? p.accent),
        title: Text(title, style: TextStyle(fontSize: 14.5, color: p.text)),
        trailing:
            trailing ?? Icon(Icons.chevron_right, color: p.textFaint),
        onTap: onTap,
      );
    }

    final spinner = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2));

    return Scaffold(
      backgroundColor: p.bgList,
      appBar: AppBar(
        backgroundColor: p.bgList,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(tr('about_title'),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textSoft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
                color: p.bgChat, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset('assets/icon.png',
                      width: 72, height: 72, fit: BoxFit.cover),
                ),
                const SizedBox(height: 10),
                Text('TN ${appBuildVersion.replaceFirst('v', '')}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
                const SizedBox(height: 4),
                Text(tr('about_tagline'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: p.textSoft)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: p.bgChat, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                tile(Icons.history_edu, tr('about_changelog'),
                    onTap: _openChangelog,
                    trailing: _loadingChangelog
                        ? spinner
                        : Icon(Icons.chevron_right, color: p.textFaint)),
                Divider(height: 8, color: p.divider),
                tile(Icons.system_update_alt, tr('about_check_updates'),
                    onTap: _checkUpdates,
                    trailing: _checking
                        ? spinner
                        : Icon(Icons.chevron_right, color: p.textFaint)),
                Divider(height: 8, color: p.divider),
                tile(Icons.favorite_outline, 'ko-fi',
                    iconColor: const Color(0xFFFF5E5B), onTap: _openKofi),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
