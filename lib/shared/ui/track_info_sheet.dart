/// Track info: what the platform knows beyond title and artist. Album, year,
/// duration, publisher, genres, description; empty fields don't show at all.
/// Opens from the actions sheet and should look like its continuation, so the
/// header is the same.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../util/format.dart';
import 'bloom_icon.dart';
import 'bloom_sheet.dart';
import '../../shared/ui/atoms.dart';

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
    // A file path only for local tracks; platform ones have none.
    final file = switch (track.sourceData) {
      {'file': final String path} when path.trim().isNotEmpty => path,
      {'name': final String name} when name.trim().isNotEmpty => name,
      _ => null,
    };
    // Zero means the platform didn't send it, not a zero-length track.
    final duration = track.duration > Duration.zero
        ? mmss(track.duration)
        : null;
    // Full release date when the platform knows day and month (SoundCloud,
    // Yandex); with only the year, the row stays Year.
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
      if (track.genres.isNotEmpty)
        _InfoRow(
          label: l.tiGenres,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final genre in track.genres)
                  BloomTag(text: genre, active: false),
              ],
            ),
          ),
        ),
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
        // An empty track is an answer too: saying so in words beats an empty
        // sheet.
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, this.value, this.child});

  final String label;
  final String? value;

  /// Instead of [value].
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.bodySmall),
          const SizedBox(height: 3),
          child ?? Text(value!, style: theme.titleMedium),
        ],
      ),
    );
  }
}

/// The E mark: the only track field with a fact rather than a value, so it's a
/// first row; the header is shared by sheets.
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
