/// Presets tab of customization, snapshots of applied pictures: a grid of cards
/// with a preview carousel, creating by name, exporting and importing
/// `.bloompresets`. A sheet on tap for actions; creating and importing share
/// one sheet under the plus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/pressable.dart';
import '../media_store.dart';
import '../presets_file.dart';
import '../presets_store.dart';
import 'custom_sheet.dart';
import 'custom_widgets.dart';

class PresetsPane extends ConsumerWidget {
  const PresetsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider);
    return CustomPane(
      empty: context.l.custPresetsEmpty,
      itemCount: presets.length,
      itemBuilder: (_, i) => _PresetCard(preset: presets[i]),
    );
  }
}

/// The tab's plus: a new preset's name in the field, switches under it for what
/// else goes in (theme, transparency, font), and file Import at the very
/// bottom.
Future<void> showAddPresetSheet(BuildContext context, WidgetRef ref) async {
  final l10n = context.l;
  final picked = await showBloomSheetChild<Object>(
    context: context,
    child: const _PresetAddForm(),
  );
  if (picked == null) return;
  if (picked is _NewPreset) {
    final saved = ref
        .read(presetsProvider.notifier)
        .save(
          picked.name,
          theme: picked.theme,
          transparency: picked.transparency,
          font: picked.font,
        );
    // Two different refusals: the limit was hit, or nothing to snapshot with no
    // context taken.
    final failure = ref.read(presetsProvider).length >= kPresetsLimit
        ? l10n.custPresetsFull(kPresetsLimit)
        : l10n.custPresetNothing;
    toaster.show(
      saved == null ? failure : l10n.custPresetSaved(saved.name),
      kind: saved == null ? ToastKind.warn : ToastKind.success,
    );
    return;
  }
  final content = await openTextFile();
  if (content == null) return;
  final added = await importPresets(ref.read, content);
  toaster.show(
    added == 0 ? l10n.custImportBad : l10n.custImported(added),
    kind: added == 0 ? ToastKind.warn : ToastKind.success,
  );
}

/// What was picked in the creation sheet.
class _NewPreset {
  const _NewPreset({
    required this.name,
    required this.theme,
    required this.transparency,
    required this.font,
  });

  final String name;
  final bool theme;
  final bool transparency;
  final bool font;
}

/// Creation sheet: a name field, switches for what else goes in, and Import.
/// Closes with [_NewPreset] or `true` (import).
class _PresetAddForm extends StatefulWidget {
  const _PresetAddForm();

  @override
  State<_PresetAddForm> createState() => _PresetAddFormState();
}

class _PresetAddFormState extends State<_PresetAddForm> {
  final _name = TextEditingController();
  bool _theme = false;
  bool _transparency = false;
  bool _font = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _NewPreset(
        name: name,
        theme: _theme,
        transparency: _transparency,
        font: _font,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) =>
        SheetSwitchRow(
          label: label,
          value: value,
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetField(
          controller: _name,
          hint: context.l.custPresetNameHint,
          autofocus: true,
          maxLength: 40,
          onChanged: (_) => setState(() {}),
          onSubmit: _submit,
        ),
        // Pictures with blur, dim and cover mode always go in; this is
        // optional.
        SheetCaption(context.l.custPresetAlsoSave),
        SheetPanel(
          children: [
            toggle(
              context.l.custPresetTheme,
              _theme,
              (v) => setState(() => _theme = v),
            ),
            sheetDivider(indent: 18),
            toggle(
              context.l.custPresetTransparency,
              _transparency,
              (v) => setState(() => _transparency = v),
            ),
            sheetDivider(indent: 18),
            toggle(
              context.l.custPresetFont,
              _font,
              (v) => setState(() => _font = v),
            ),
          ],
        ),
        SheetPickRow(icon: Bi.import, label: context.l.custImport),
      ],
    );
  }
}

class _PresetCard extends ConsumerWidget {
  const _PresetCard({required this.preset});

  final Preset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final lib = ref.watch(mediaLibProvider);
    final srcs = [
      for (final id in preset.imageIds)
        for (final item in lib)
          if (item.id == id) item.src,
    ];

    return Pressable(
      onTap: () => _openSheet(context, ref, srcs),
      scale: 0.97,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius * 0.85),
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.pill),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PresetThumb(srcs: srcs),
              // A caption plate at the bottom edge, over the picture rather
              // than under it.
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Text(
                    preset.name.isEmpty
                        ? context.l.custPresetUntitled
                        : preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref,
    List<String> srcs,
  ) {
    final l10n = context.l;
    final name = preset.name.isEmpty ? l10n.custPresetUntitled : preset.name;

    /// An item closes the sheet before acting, like sheet menu items.
    VoidCallback close(BuildContext sheet, VoidCallback action) => () {
      Navigator.of(sheet).pop();
      action();
    };

    return showBloomSheetChild<void>(
      context: context,
      header: CustSheetPreview(srcs: srcs),
      footer: Builder(
        builder: (sheet) => CustSheetDelete(
          onTap: close(
            sheet,
            () => ref.read(presetsProvider.notifier).delete(preset.id),
          ),
        ),
      ),
      child: Builder(
        builder: (sheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preset name as a caption over the block.
            SheetCaption(name),
            SheetPanel(
              children: [
                SheetRow(
                  icon: Bi.checkCircle,
                  label: l10n.custPresetApply,
                  onTap: close(sheet, () {
                    ref.read(presetsProvider.notifier).apply(preset.id);
                    toaster.show(
                      l10n.custPresetApplied(preset.name),
                      kind: ToastKind.success,
                    );
                  }),
                ),
                sheetDivider(indent: 60),
                SheetRow(
                  icon: Bi.export,
                  label: l10n.custPresetExport,
                  onTap: close(sheet, () async {
                    final content = await encodePresets([
                      preset,
                    ], ref.read(mediaLibProvider));
                    final ok = await saveTextFile(
                      presetFileName(preset.name),
                      content,
                    );
                    // A cancelled dialog is no reason for a toast: the user
                    // closed it.
                    if (ok) {
                      toaster.show(
                        l10n.custPresetExported,
                        kind: ToastKind.success,
                      );
                    }
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Preset preview: its pictures flip by themselves every 2.2 s. One picture is
/// just a picture, zero a box icon.
class PresetThumb extends StatefulWidget {
  const PresetThumb({super.key, required this.srcs});

  final List<String> srcs;

  @override
  State<PresetThumb> createState() => _PresetThumbState();
}

class _PresetThumbState extends State<PresetThumb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _cycle.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      setState(() => _index = (_index + 1) % widget.srcs.length);
      _cycle.forward(from: 0);
    });
    if (widget.srcs.length > 1) _cycle.forward();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    if (widget.srcs.isEmpty) {
      return Center(
        child: BloomIcon(Bi.boxMinimalistic, size: 26, color: t.muted),
      );
    }
    final image = coverImage(widget.srcs[_index % widget.srcs.length]);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: image == null
          ? const SizedBox.expand()
          : Image(
              key: ValueKey(_index),
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
    );
  }
}
