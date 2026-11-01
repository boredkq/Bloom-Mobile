/// SoundCloud: a typed `client_id` and a connection check, on the
/// [PlatformPage] layout. Collapsed at rest: the key is found on its own, and
/// "Set up" opens the guide, the field and the check.
///
/// Saving by hand drops the found key; the check drops it too and searches, so
/// it shows which key really works now.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../providers/soundcloud/models.dart';
import '../../../providers/soundcloud/soundcloud.dart' as sc;
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import 'platform_page.dart';

class SoundCloudSettingsScreen extends ConsumerStatefulWidget {
  const SoundCloudSettingsScreen({super.key});

  @override
  ConsumerState<SoundCloudSettingsScreen> createState() =>
      _SoundCloudSettingsScreenState();
}

class _SoundCloudSettingsScreenState
    extends ConsumerState<SoundCloudSettingsScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(settingsProvider).scClientId ?? '',
  );

  /// One's own key is rarely needed.
  bool _open = false;
  bool _checking = false;
  ScCheckResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(settingsProvider.notifier).setScClientId(_controller.text);
    setState(() {});
  }

  void _clear() {
    _controller.clear();
    ref.read(settingsProvider.notifier).setScClientId(null);
    setState(() {});
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await sc.checkConnection();
    if (!mounted) return;
    // Found one on its own and the field is empty: I put it there to save.
    if (result.ok && _controller.text.trim().isEmpty) {
      final id = result.clientId;
      if (id != null) _controller.text = id;
    }
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  void _guide() => showPlatformGuide(
    context,
    mark: const BrandMark.platform(MusicSource.soundcloud),
    title: context.l.scGuideTitle,
    steps: [
      context.l.scStep1,
      context.l.scStep2,
      context.l.scStep3,
      context.l.scStep4,
      context.l.scStep5,
    ],
    note: context.l.scHelp,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final saved = ref.watch(settingsProvider).scClientId;

    return PlatformPage(
      mark: const BrandMark.platform(MusicSource.soundcloud),
      onBack: () => context.go('/settings'),
      status: saved == null ? l.scStatusAuto : l.scStatusManual,
      body: _open ? _buildForm(saved) : null,
      actions: [
        BloomButton(
          label: _open
              ? l.commonHide
              : saved == null
              ? l.scSetup
              : l.scReconfigure,
          tone: ButtonTone.plate,
          pill: false,
          height: 54,
          onTap: () => setState(() => _open = !_open),
        ),
      ],
    );
  }

  Widget _buildForm(String? saved) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    // An unsaved edit: the left button offers to save, otherwise it clears the
    // saved key.
    final changed = _controller.text.trim() != (saved ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformCard(
          mark: const BrandMark.platform(MusicSource.soundcloud),
          title: l.scGuideTitle,
          subtitle: l.scGuideSubtitle,
          onTap: _guide,
        ),
        const Center(child: OrLabel()),
        GlassBox(
          borderRadius: BorderRadius.circular(t.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    cursorColor: t.accent,
                    style: theme.bodyMedium?.copyWith(color: t.text),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      hintText: l.scHint,
                      hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
                    ),
                  ),
                ),
                // The guide is needed exactly when looking at an empty field.
                CircleIconButton(
                  icon: Bi.questionCircle,
                  size: 48,
                  iconSize: 20,
                  background: Colors.transparent,
                  color: t.muted,
                  onTap: _guide,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BloomButton(
                label: changed ? l.commonSave : l.commonClear,
                tone: ButtonTone.plate,
                pill: false,
                height: 48,
                onTap: changed
                    ? _save
                    : saved == null && _controller.text.isEmpty
                    ? null
                    : _clear,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BloomButton(
                label: l.scCheckConnection,
                tone: ButtonTone.plate,
                pill: false,
                height: 48,
                busy: _checking,
                onTap: _check,
              ),
            ),
          ],
        ),
        if (_result case final r?) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              BloomIcon(
                r.ok ? Bi.check : Bi.close,
                size: 18,
                color: r.ok ? kPlatformOk : t.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.ok ? l.scConnectionOk : l.scConnectionFail,
                  style: theme.bodyMedium?.copyWith(color: t.text),
                ),
              ),
            ],
          ),
          if (r.clientId case final id?) ...[
            const SizedBox(height: 6),
            Text('${l.scActiveKey}: $id', style: theme.bodySmall),
          ],
          if (r.error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: theme.bodySmall?.copyWith(color: t.danger)),
          ],
        ],
      ],
    );
  }
}
