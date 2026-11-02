/// The build's version and the update check: GitHub releases compared with
/// what's installed, and a link to the release page if newer. An APK is
/// installed by the system and App Store updates by itself, so there's no
/// installer here.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/log/bloom_log.dart';
import '../../core/store/text_files.dart';

/// Where the APK and the notes are published.
const String kUpdateRepo = 'use-bloom/mobile';

Uri get _latestUrl =>
    Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest');

enum UpdatePhase { idle, checking, uptodate, available, error }

class AboutState {
  const AboutState({
    this.version = '',
    this.phase = UpdatePhase.idle,
    this.latest = '',
    this.releaseUrl = '',
  });

  /// The installed version; empty if the platform didn't answer. The build
  /// number stays out: it grows with each build and says nothing to anyone.
  final String version;

  final UpdatePhase phase;

  /// Without `v`; only after a successful check.
  final String latest;
  final String releaseUrl;

  AboutState copyWith({
    String? version,
    UpdatePhase? phase,
    String? latest,
    String? releaseUrl,
  }) => AboutState(
    version: version ?? this.version,
    phase: phase ?? this.phase,
    latest: latest ?? this.latest,
    releaseUrl: releaseUrl ?? this.releaseUrl,
  );
}

/// A provider for tests.
typedef ReleaseFetch = Future<String> Function(Uri url);

final releaseFetchProvider = Provider<ReleaseFetch>((ref) => _get);

Future<String> _get(Uri url) async {
  final res = await http.get(
    url,
    headers: {'Accept': 'application/vnd.github+json'},
  );
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', url);
  }
  return res.body;
}

final aboutProvider = NotifierProvider<AboutController, AboutState>(
  AboutController.new,
);

class AboutController extends Notifier<AboutState> {
  @override
  AboutState build() => const AboutState();

  /// Safe to repeat: the screen calls it on each opening and the answer holds
  /// until reinstalling.
  Future<void> loadVersion() async {
    if (state.version.isNotEmpty) return;
    final info = await appVersion();
    if (info == null) return;
    state = state.copyWith(version: info.version);
  }

  /// A second call during the first is ignored.
  Future<void> check() async {
    if (state.phase == UpdatePhase.checking) return;
    state = state.copyWith(phase: UpdatePhase.checking);
    try {
      final body = await ref.read(releaseFetchProvider)(_latestUrl);
      final rel = jsonDecode(body);
      if (rel is! Map || rel['tag_name'] is! String) {
        throw const FormatException('not a release');
      }
      final latest = normalizeVersion(rel['tag_name'] as String);
      final url =
          rel['html_url'] as String? ??
          'https://github.com/$kUpdateRepo/releases';
      // Version unknown: "release N is out" is more honest than "you have the
      // latest".
      final newer =
          state.version.isEmpty || compareVersions(latest, state.version) > 0;
      state = state.copyWith(
        phase: newer ? UpdatePhase.available : UpdatePhase.uptodate,
        latest: latest,
        releaseUrl: url,
      );
    } catch (e) {
      logWarn('update', 'update check failed: $e');
      state = state.copyWith(phase: UpdatePhase.error);
    }
  }
}

/// Tags, build names and manifest versions compare in one form.
String normalizeVersion(String raw) {
  final v = raw.trim();
  return v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v;
}

/// By numeric parts. Different lengths compare as padded with zeros (`1.2` =
/// `1.2.0`); a non-numeric tail is dropped, so someone's odd tag can't break
/// the check.
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}

/// `x.y.0`: its note shows a picture and a summary.
bool isMajorVersion(String v) {
  final parts = _parts(v);
  return parts.length < 3 || parts[2] == 0;
}

List<int> _parts(String v) => [
  for (final chunk in normalizeVersion(v).split('.'))
    int.tryParse(RegExp(r'^\d+').firstMatch(chunk)?.group(0) ?? '') ?? 0,
];
