/// Секция «Источники обновления» в правке плейлиста — порт десктопного
/// `PlSourcesEditor`.
///
/// Показывает привязанные коллекции (плейлисты/альбомы/лайки любых площадок) и
/// даёт привязать новую вставкой ссылки: по «Привязать» ссылка резолвится тем
/// же путём, что и импорт (`resolveCollectionUrl`), — так проверяем, что это
/// вообще коллекция, и заодно забираем её id, название и владельца.
///
/// Черновик живёт у родителя ([ListEditor]) и записывается только по ✓, как имя
/// и обложка: сеть здесь дёргается сразу, а вот сама привязка — нет.
///
/// На странице правки секции больше нет: она стоит за кнопкой в шапке и
/// открывается шторкой ([showPlSourcesSheet]) — между обложкой и треками она
/// разрывала список и читалась как довесок к первой строке.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../import_url.dart';
import 'create_playlist_sheet.dart' show detectLinkSource;

/// Открыть источники шторкой. Правки уходят наверх [onChanged] по мере дела, а
/// не по закрытию: шторку бросают и свайпом, и «назад», и терять привязки на
/// этом нельзя. В сам плейлист они всё так же попадают только по ✓ страницы.
Future<void> showPlSourcesSheet(
  BuildContext context, {
  required List<PlSourceRef> sources,
  required ValueChanged<List<PlSourceRef>> onChanged,
}) {
  return showBloomSheetChild<void>(
    context: context,
    child: _PlSourcesSheet(sources: sources, onChanged: onChanged),
  );
}

/// Черновик источников на время жизни шторки: страница под ней уже не
/// перестраивается, и обновлять список привязок некому.
class _PlSourcesSheet extends StatefulWidget {
  const _PlSourcesSheet({required this.sources, required this.onChanged});

  final List<PlSourceRef> sources;
  final ValueChanged<List<PlSourceRef>> onChanged;

  @override
  State<_PlSourcesSheet> createState() => _PlSourcesSheetState();
}

class _PlSourcesSheetState extends State<_PlSourcesSheet> {
  late List<PlSourceRef> _sources = widget.sources;

  @override
  Widget build(BuildContext context) => PlSourcesEditor(
    sources: _sources,
    onChanged: (next) {
      setState(() => _sources = next);
      widget.onChanged(next);
    },
  );
}

class PlSourcesEditor extends ConsumerStatefulWidget {
  const PlSourcesEditor({
    super.key,
    required this.sources,
    required this.onChanged,
  });

  final List<PlSourceRef> sources;
  final ValueChanged<List<PlSourceRef>> onChanged;

  @override
  ConsumerState<PlSourcesEditor> createState() => _PlSourcesEditorState();
}

class _PlSourcesEditorState extends ConsumerState<PlSourcesEditor> {
  final _url = TextEditingController();

  /// Идёт резолв вставленной ссылки.
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final url = _url.text.trim();
    if (url.isEmpty || _busy) return;
    // Та же ссылка — дубль и без сети.
    if (widget.sources.any((s) => s.url == url)) {
      showToast(context, context.l.psDuplicate, kind: ToastKind.warn);
      return;
    }
    setState(() => _busy = true);
    try {
      final found = await resolveCollectionUrl(ref.read(registryProvider), url);
      if (!mounted) return;
      setState(() => _busy = false);
      // Другая ссылка на ту же коллекцию — тоже дубль: сверяем по id.
      if (widget.sources.any((s) => s.id == found.source.id)) {
        showToast(context, context.l.psDuplicate, kind: ToastKind.warn);
        return;
      }
      _url.clear();
      widget.onChanged([...widget.sources, found.source]);
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(
        context,
        describeImportFailure(context.l, e.reason),
        kind: ToastKind.warn,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, context.l.cpSourceNoAnswer, kind: ToastKind.error);
    }
  }

  void _remove(int index) => widget.onChanged([
    for (var i = 0; i < widget.sources.length; i++)
      if (i != index) widget.sources[i],
  ]);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      // По краю блоков шторки: секция живёт только в ней.
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l.psTitle, style: theme.titleMedium),
          const SizedBox(height: 4),
          Text(
            context.l.psHint,
            style: theme.bodySmall?.copyWith(color: t.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.sources.length; i++) ...[
            _SourceRow(
              source: widget.sources[i],
              onRemove: _busy ? null : () => _remove(i),
            ),
            const SizedBox(height: 8),
          ],
          SheetField(
            controller: _url,
            hint: context.l.psAddHint,
            busy: _busy,
            autocorrect: false,
            keyboardType: TextInputType.url,
            trailing: switch (detectLinkSource(_url.text)) {
              final source? => PlatformLogo(source, size: 18),
              null => null,
            },
            padding: EdgeInsets.zero,
            onChanged: (_) => setState(() {}),
            onSubmit: _add,
          ),
        ],
      ),
    );
  }
}

/// Строка привязки: знак площадки, название коллекции, под ним владелец (или
/// ссылка, если владельца площадка не сказала).
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.onRemove});

  final PlSourceRef source;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final platform = MusicSource.fromCode(source.provider);
    final title = source.title.isEmpty ? source.url : source.title;
    final under = source.owner.isEmpty ? source.url : source.owner;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        // Плашка внутри шторки красится по её скину, а не токеном страницы:
        // на стекле сплошной `pill` остался бы единственным глухим пятном.
        color: sheetPanelColor(context),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        children: [
          // Знак площадки — в фирменных цветах, как везде в приложении.
          PlatformLogo(platform, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleMedium,
                ),
                // Ссылку под названием повторять незачем, когда она и есть
                // название.
                if (under.isNotEmpty && under != title) ...[
                  const SizedBox(height: 2),
                  Text(
                    under,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          CircleIconButton(
            icon: Bi.close,
            size: 40,
            iconSize: 18,
            background: Colors.transparent,
            color: t.muted,
            tooltip: context.l.psRemove,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}
