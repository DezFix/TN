import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'app_log.dart';
import 'app_model.dart';
import 'theme.dart';
import 'updater.dart';

/// Installed version, kept in sync with pubspec.yaml.
const appBuildVersion = '1.27.5';

const _kofiUrl = 'https://ko-fi.com/k_k';
const _repoLatest = 'https://api.github.com/repos/DezFix/TN/releases/latest';
const repoPageUrl = 'https://github.com/DezFix/TN/releases/latest';

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.body,
    required this.pageUrl,
    this.apkUrl,
    this.apkSha256,
  });

  final String tag;
  final String name;
  final String body;
  final String pageUrl;
  final String? apkUrl;
  final String? apkSha256;

  bool isNewerThan(String installed) => Updater.isNewerTag(tag, installed);
}

/// Shared markdown style for release/changelog rendering.
MarkdownStyleSheet releaseSheetStyle(Palette p) => MarkdownStyleSheet(
      p: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5),
      h1: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
      h2: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
      h3: TextStyle(
          fontSize: 13.5, fontWeight: FontWeight.w700, color: p.accent),
      listBullet: TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5),
      code: TextStyle(
          fontSize: 12, color: p.textSoft, fontFamily: 'monospace'),
    );

/// Scrollable markdown view of a release body (changelog sheet reuse).
Widget releaseMarkdown(String body, Palette p, {ScrollController? controller}) =>
    SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: MarkdownBody(
          data: body, selectable: false, styleSheet: releaseSheetStyle(p)),
    );

/// Fetches the latest GitHub release. Returns null offline / rate-limited.
Future<ReleaseInfo?> fetchLatestRelease() async {
  try {
    final r = await http
        .get(Uri.parse(_repoLatest), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'TN-app',
    }).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final rel = jsonDecode(r.body) as Map<String, dynamic>;
    final tag = (rel['tag_name'] as String?) ?? '';
    final body =
        ((rel['body'] as String?) ?? '').replaceFirst(RegExp(r'^\uFEFF'), '');
    if (tag.isEmpty || body.trim().isEmpty) return null;

    final picked =
        Platform.isAndroid ? await _pickApk(rel['assets'] as List<dynamic>?) : null;
    return ReleaseInfo(
      tag: tag,
      name: (rel['name'] as String?) ?? '',
      body: body,
      pageUrl: (rel['html_url'] as String?) ?? repoPageUrl,
      apkUrl: picked?.url,
      apkSha256: picked?.sha,
    );
  } catch (e, st) {
    AppLog.error('update.fetch', e, st);
    return null;
  }
}

/// Only .apk files are installable — picks the variant matching the installed
/// APK (universal vs split) so versionCode never downgrades (78 vs 2078).
Future<({String url, String sha})?> _pickApk(List<dynamic>? assets) async {
  if (assets == null) return null;
  String? universalUrl, universalSha;
  String? arm64Url, arm64Sha;
  String? x86Url, x86Sha;
  String? fallbackUrl, fallbackSha;
  for (final a in assets) {
    final map = a as Map<String, dynamic>;
    final n = (map['name'] as String?) ?? '';
    if (!n.toLowerCase().endsWith('.apk')) continue;
    final u = map['browser_download_url'] as String? ?? '';
    final digest = (map['digest'] as String?) ?? '';
    final sha = digest.startsWith('sha256:') ? digest.substring(7) : '';
    final lower = n.toLowerCase();
    if (lower.contains('universal')) {
      universalUrl = u;
      universalSha = sha.isNotEmpty ? sha : null;
    } else if (lower.contains('arm64')) {
      arm64Url ??= u;
      arm64Sha ??= sha.isNotEmpty ? sha : null;
    } else if (lower.contains('x86_64') || lower.contains('x86')) {
      x86Url ??= u;
      x86Sha ??= sha.isNotEmpty ? sha : null;
    } else if (fallbackUrl == null) {
      fallbackUrl = u;
      fallbackSha = sha.isNotEmpty ? sha : null;
    }
  }
  // Detect installed variant to avoid universal↔split downgrade (78 vs 2078)
  String abi = 'arm64-v8a';
  bool isUniversal = true;
  try {
    abi = await AppInfo.getAbi();
    isUniversal = await AppInfo.isUniversal();
  } catch (_) {}
  if (isUniversal && universalUrl != null) {
    return (url: universalUrl, sha: universalSha ?? '');
  }
  if (abi.contains('arm64') && arm64Url != null) {
    return (url: arm64Url, sha: arm64Sha ?? '');
  }
  if ((abi.contains('x86_64') || abi.contains('x86')) && x86Url != null) {
    return (url: x86Url, sha: x86Sha ?? '');
  }
  // Fallback chain: universal -> arm64 -> x86 -> any apk
  if (universalUrl != null) return (url: universalUrl, sha: universalSha ?? '');
  if (arm64Url != null) return (url: arm64Url, sha: arm64Sha ?? '');
  if (x86Url != null) return (url: x86Url, sha: x86Sha ?? '');
  if (fallbackUrl != null) return (url: fallbackUrl, sha: fallbackSha ?? '');
  return null;
}

/// Cold-start flow: "What's new" once per unseen tag + a single update nudge.
Future<void> maybeShowWhatsNew(BuildContext context, AppModel model) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final rel = await fetchLatestRelease();
    if (rel == null || !context.mounted) return;

    if (prefs.getString('tn-seen-release') != rel.tag && context.mounted) {
      await showReleaseDialog(context, model,
          title: rel.name.isNotEmpty ? rel.name : 'TN ${rel.tag}',
          markdown: rel.body,
          updateUrl: rel.isNewerThan(appBuildVersion) ? rel.pageUrl : null,
          apkUrl: rel.apkUrl,
          apkSha256: rel.apkSha256);
      await prefs.setString('tn-seen-release', rel.tag);
      return;
    }

    // Already seen this changelog — still nudge once per tag when an update
    // is pending ("Later" pressed before).
    if (rel.isNewerThan(appBuildVersion) &&
        prefs.getString('tn-update-prompted') != rel.tag &&
        context.mounted) {
      await showUpdateDialog(context, model, rel.tag,
          url: rel.pageUrl, apkUrl: rel.apkUrl, apkSha256: rel.apkSha256);
      await prefs.setString('tn-update-prompted', rel.tag);
    }
  } catch (_) {}
}

/// Manual "Check for updates": ignores seen-flags and always reports back.
Future<void> manualCheckForUpdate(BuildContext context, AppModel model) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final rel = await fetchLatestRelease();
  if (!context.mounted && messenger == null) return;

  void toast(String key, [List<String>? args]) =>
      messenger?.showSnackBar(SnackBar(
          content: Text(model.tr(key, args)),
          backgroundColor: model.p.bgChat));

  if (rel == null) {
    toast('update_check_failed');
    return;
  }
  if (!rel.isNewerThan(appBuildVersion)) {
    toast('update_latest', [rel.tag.replaceFirst('v', '')]);
    return;
  }
  await showUpdateDialog(context, model, rel.tag,
      url: rel.pageUrl, apkUrl: rel.apkUrl, apkSha256: rel.apkSha256);
}

// ---------------------------------------------------------------- dialogs

Future<void> showUpdateDialog(
  BuildContext context,
  AppModel model,
  String tag, {
  required String url,
  String? apkUrl,
  String? apkSha256,
}) async {
  final p = model.p;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      bool downloading = false;
      double progress = 0;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: p.modalBg,
          title: Text(model.tr('update_available'),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          content: downloading
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: p.accent,
                      backgroundColor: p.divider),
                  const SizedBox(height: 12),
                  Text(model.tr('downloading'),
                      style: TextStyle(fontSize: 13.5, color: p.textSoft)),
                ])
              : Text(model.tr('update_hint', [tag]),
                  style:
                      TextStyle(fontSize: 13.5, color: p.textSoft, height: 1.5)),
          actions: [
            TextButton(
              onPressed: downloading ? null : () => Navigator.pop(ctx),
              child:
                  Text(model.tr('later'), style: TextStyle(color: p.textSoft)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.accent),
              icon: Icon(downloading ? Icons.hourglass_empty : Icons.download,
                  size: 18),
              onPressed: downloading
                  ? null
                  : () async {
                      if (apkUrl != null && Platform.isAndroid) {
                        setDialogState(() {
                          downloading = true;
                          progress = 0;
                        });
                        final result =
                            await Updater.downloadAndInstall(apkUrl, (pr) {
                          setDialogState(() => progress = pr);
                        }, expectedSha256: apkSha256);
                        if (result == null && ctx.mounted) {
                          setDialogState(() => downloading = false);
                          final reinstall =
                              Updater.lastError == 'INSTALL_FAILED';
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(reinstall
                                ? model.tr('update_reinstall')
                                : model.tr('download_failed')),
                          ));
                        }
                      } else {
                        Navigator.pop(ctx);
                        _launch(url);
                      }
                    },
              label: Text(model.tr('update_now')),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showReleaseDialog(
  BuildContext context,
  AppModel model, {
  required String title,
  required String markdown,
  String? updateUrl,
  String? apkUrl,
  String? apkSha256,
}) async {
  final p = model.p;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      bool downloading = false;
      double progress = 0;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: p.modalBg,
          title: Text(title,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          content: SizedBox(
            width: 340,
            child: downloading
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        color: p.accent,
                        backgroundColor: p.divider),
                    const SizedBox(height: 12),
                    Text(model.tr('downloading'),
                        style:
                            TextStyle(fontSize: 13.5, color: p.textSoft)),
                  ])
                : SingleChildScrollView(child: releaseMarkdown(markdown, p)),
          ),
          actions: [
            TextButton(
              onPressed: downloading
                  ? null
                  : () async {
                      await Clipboard.setData(
                          const ClipboardData(text: _kofiUrl));
                      var opened = false;
                      try {
                        opened = await launchUrl(Uri.parse(_kofiUrl),
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      final mountedNow = context.mounted;
                      if (mountedNow && messenger != null) {
                        messenger.showSnackBar(SnackBar(
                          content: Text(opened
                              ? model.tr('support')
                              : 'ko-fi.com/k_k • ${model.tr('support')}'),
                        ));
                      }
                    },
              child: Text('❤ ko-fi', style: TextStyle(color: p.accent)),
            ),
            if (updateUrl != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.accent),
                icon: Icon(
                    downloading ? Icons.hourglass_empty : Icons.download,
                    size: 18),
                onPressed: downloading
                    ? null
                    : () async {
                        if (apkUrl != null && Platform.isAndroid) {
                          setDialogState(() {
                            downloading = true;
                            progress = 0;
                          });
                          final result =
                              await Updater.downloadAndInstall(apkUrl, (pr) {
                            setDialogState(() => progress = pr);
                          }, expectedSha256: apkSha256);
                          if (result == null && ctx.mounted) {
                            setDialogState(() => downloading = false);
                            final reinstall =
                                Updater.lastError == 'INSTALL_FAILED';
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                              content: Text(reinstall
                                  ? model.tr('update_reinstall')
                                  : model.tr('download_failed')),
                            ));
                          }
                        } else {
                          Navigator.pop(ctx);
                          _launch(updateUrl!);
                        }
                      },
                label: Text(model.tr('update_now')),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: p.accent),
                onPressed: () => Navigator.pop(ctx),
                child: Text(model.tr('close')),
              ),
          ],
        ),
      );
    },
  );
}

void _launch(String url) {
  try {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}
