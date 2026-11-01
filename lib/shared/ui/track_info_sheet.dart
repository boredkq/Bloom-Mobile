/// «Инфо о треке» — то, что площадка знает о треке сверх названия и артиста.
///
/// Порт десктопной `TrackInfoModal`: тот же состав (альбом, год, длительность,
/// паблишер, жанры, описание) и тот же принцип — пустые поля не показываются
/// вовсе, а не стоят прочерками. На телефоне это не модалка по центру, а
/// нижняя шторка: открывается она из шторки действий и обязана выглядеть её
/// продолжением, поэтому шапка у них одна и та же.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../util/format.dart';
import 'bloom_icon.dart';
import 'bloom_sheet.dart';

/// [addedAt] is when the track came into the library: the header is the same as
/// in the actions sheet. The caller reads it: no `ref` comes into the sheet.
Future<void> showTrackInfoSheet(
  BuildContext context,
  Track track, {
  int? addedAt,
}) {
  return showBloomSheetChild<void>(
    context: context,
    header: SheetHero(
      cover: track.cover,
      title: track.name,
      subtitle: track.artist,
      meta: sheetDateMeta(context, context.l.commonAddedOn, addedAt),
    ),
    child: _TrackInfo(track: track),
  );
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    // Файл — только у своих треков: у площадочных пути нет и строка стояла бы
    // пустой (на ПК ровно то же условие).
    final file = switch (track.sourceData) {
      {'file': final String path} when path.trim().isNotEmpty => path,
      {'name': final String name} when name.trim().isNotEmpty => name,
      _ => null,
    };
    // Длительность нулевая — значит площадка её не отдала, а не «трек длиной
    // ноль»: показывать нечего.
    final duration = track.duration > Duration.zero
        ? mmss(track.duration)
        : null;
    // Полная дата релиза, когда площадка знает день и месяц (SoundCloud,
    // Яндекс); знает только год — строка остаётся прежним «Годом».
    final released = releaseDateLabel(
      track.releaseDate,
      Localizations.localeOf(context).toString(),
    );

    final rows = <Widget>[
      if (track.creditedArtist case final credited?)
        if (credited != track.artist)
          _InfoRow(label: l.tiCredited, value: credited),
      if (track.album case final album?)
        _InfoRow(label: l.tiAlbum, value: album),
      if (released != null)
        _InfoRow(label: l.tiReleased, value: released)
      else if (track.year case final year?)
        _InfoRow(label: l.tiYear, value: year),
      if (duration != null) _InfoRow(label: l.tiDuration, value: duration),
      if (track.publisher case final publisher?)
        _InfoRow(label: l.tiPublisher, value: publisher),
      if (track.genres.isNotEmpty) _GenresRow(genres: track.genres),
      if (file != null) _InfoRow(label: l.tiFile, value: file),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track.explicit) const _ExplicitMark(),
        if (rows.isNotEmpty) SheetPanel(children: rows),
        if (track.description case final description?)
          if (description.trim().isNotEmpty)
            SheetPanel(
              children: [
                _InfoRow(label: l.tiDescription, value: description.trim()),
              ],
            ),
        // Совсем пустой трек — тоже ответ: сказать это словами честнее, чем
        // открыть шторку без единой строки.
        if (rows.isEmpty && (track.description ?? '').trim().isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Text(
              l.tiNothing,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

/// Строка «подпись сверху, значение снизу» — как ячейка `.ti-cell` на ПК.
/// Значение не режем: длинный путь к файлу и описание должны читаться целиком.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // `stretch`, а не `start`: колонка со `start` ужимается по своему тексту,
      // а блок шторки ставит детей по центру — короткие строки («Год»)
      // уезжали к середине, длинные оставались у края.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.bodySmall),
          const SizedBox(height: 3),
          Text(value, style: theme.titleMedium),
        ],
      ),
    );
  }
}

/// Жанры — плашками, а не строкой через запятую: их бывает пять, и списком они
/// читаются быстрее (десктопные `.ti-genre-tag`).
class _GenresRow extends StatelessWidget {
  const _GenresRow({required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        // Ширину держит `Wrap`: он и так занимает всю строку блока, отдельная
        // распорка тут не нужна.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l.tiGenres, style: theme.bodySmall),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final genre in genres)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: sheetLineColor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    genre,
                    style: theme.bodyMedium?.copyWith(color: t.text),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Пометка «E» — единственное поле трека, у которого нет значения, только
/// факт: на ПК она стоит рядом с названием в шапке, здесь — первой строкой,
/// потому что шапка у шторок общая.
class _ExplicitMark extends StatelessWidget {
  const _ExplicitMark();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          BloomIcon(Bi.dangerCircle, size: 16, color: t.muted),
          const SizedBox(width: 8),
          Text(
            context.l.tiExplicit,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
