/// Вкладка «Пресеты» страницы «Кастомизация» — снимки применённых картинок.
///
/// Порт десктопной вкладки пресетов из `CustomizationSection.tsx`: сетка
/// карточек с превью-каруселью, создание по имени, экспорт и импорт файла
/// `.bloompresets`. Контекстное меню правой кнопкой там — здесь наша шторка по
/// тапу (`showBloomSheet`), как у всего остального в приложении. Создание и
/// импорт — одна шторка под плюсиком (имя в поле, «Импорт» под ним).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/pressable.dart';
import '../media_store.dart';
import '../presets_file.dart';
import '../presets_store.dart';
import 'custom_sheet.dart';
import 'custom_widgets.dart';
import '../../../shared/ui/subpage_header.dart';

class PresetsPane extends ConsumerWidget {
  const PresetsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider);
    if (presets.isEmpty) {
      return Center(
        child: CenterNote(
          context.l.custPresetsEmpty,
          padding: const EdgeInsets.symmetric(horizontal: 40),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 8 + bottomBarsInset(context)),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 4 / 3,
      ),
      itemCount: presets.length,
      itemBuilder: (_, i) => _PresetCard(preset: presets[i]),
    );
  }
}

/// Плюсик вкладки: имя нового пресета в поле, под ним тумблеры «что ещё
/// положить в пресет» (тема, прозрачность, шрифт), «Импорт» файла — пунктом в
/// самом низу.
Future<void> showAddPresetSheet(BuildContext context, WidgetRef ref) async {
  final l10n = context.l;
  final messenger = ScaffoldMessenger.of(context);
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
    // Два разных отказа: упёрлись в лимит или нечего снимать — ни один
    // контекст не занят.
    final failure = ref.read(presetsProvider).length >= kPresetsLimit
        ? l10n.custPresetsFull(kPresetsLimit)
        : l10n.custPresetNothing;
    messenger.toast(
      saved == null ? failure : l10n.custPresetSaved(saved.name),
      kind: saved == null ? ToastKind.warn : ToastKind.success,
    );
    return;
  }
  final content = await openTextFile();
  if (content == null) return;
  final added = await importPresets(ref.read, content);
  messenger.toast(
    added == 0 ? l10n.custImportBad : l10n.custImported(added),
    kind: added == 0 ? ToastKind.warn : ToastKind.success,
  );
}

/// Что выбрали в шторке создания.
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

/// Шторка создания: поле имени, тумблеры «что ещё положить в пресет» и
/// «Импорт». Закрывается [_NewPreset] или `true` (импорт).
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
    final t = context.bloom;
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) =>
        InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                BloomSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
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
        // Картинки с размытием, затемнением и режимом обложки ложатся в
        // пресет всегда; это — по желанию.
        Padding(
          padding: const EdgeInsets.fromLTRB(kSheetEdge + 4, 10, kSheetEdge, 2),
          child: Text(
            context.l.custPresetAlsoSave,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.text2),
          ),
        ),
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
              // Подпись — плашкой у нижнего края, как на макете: поверх
              // картинки, а не под ней.
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
    final messenger = ScaffoldMessenger.of(context);
    final name = preset.name.isEmpty ? l10n.custPresetUntitled : preset.name;

    /// Пункт закрывает шторку до действия — как пункты меню шторок.
    VoidCallback close(BuildContext sheet, VoidCallback action) => () {
      Navigator.of(sheet).pop();
      action();
    };

    return showBloomSheetChild<void>(
      context: context,
      header: CustSheetPreview(srcs: srcs),
      footer: Builder(
        builder: (sheet) => CustSheetFooterButton(
          label: l10n.commonDelete,
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
            // Имя пресета — подписью над блоком, как «Применить к» у картинки.
            CustSheetLabel(name),
            CustSheetBlock(
              children: [
                CustSheetRow(
                  icon: Bi.checkCircle,
                  label: l10n.custPresetApply,
                  onTap: close(sheet, () {
                    ref.read(presetsProvider.notifier).apply(preset.id);
                    messenger.toast(
                      l10n.custPresetApplied(preset.name),
                      kind: ToastKind.success,
                    );
                  }),
                ),
                const GroupDivider(indent: kCustRowText),
                CustSheetRow(
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
                    // Отмена диалога — не повод для тоста: человек сам закрыл
                    // окно.
                    if (ok) {
                      messenger.toast(
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

/// Превью пресета: все его картинки листаются сами, как на десктопе
/// (`PresetThumb`, смена каждые 2.2 с). Одна картинка — просто картинка, ноль —
/// значок коробки.
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
