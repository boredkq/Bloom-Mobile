/// Offline actions with feedback: the store silently returns a result, and
/// telling the user happens here. The messenger comes from outside rather than
/// `context`: the actions sheet closes BEFORE the handler runs, and by the
/// snack bar its `context` has left the tree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'file_download.dart';
import 'offline_store.dart';

/// Downloads a track or removes its copy. Translations come beside the
/// messenger for the same reason: the sheet closes before the result arrives.
Future<void> toggleTrackOffline(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  Track track,
) async {
  final offline = ref.read(offlineProvider.notifier);
  if (offline.has(track.id)) {
    await offline.remove(track.id);
    messenger.toast(l.ofRemoved);
    return;
  }
  // One toast for the whole operation: the spinner turns into a tick in place
  // rather than two toasts in a row.
  final toast = messenger.busyToast(l.ofSaving);
  final error = await offline.download(track);
  toast.finish(
    error == null
        ? l.ofAvailable(track.name)
        : describeOfflineFailure(l, error),
    kind: error == null ? ToastKind.success : ToastKind.error,
  );
}

/// Downloads a whole list. [sourceId] is the list's id, telling the batch
/// indicator whose page to show on.
Future<void> downloadListOffline(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  String sourceId,
  List<Track> tracks,
) async {
  final toast = messenger.busyToast(
    l.ofSaving,
    content: (view) => BatchToastBody(view: view),
  );
  final result = await ref
      .read(offlineProvider.notifier)
      .downloadAll(sourceId, tracks);
  toast.finish(switch (result) {
    null => l.ofNothingToSave,
    final r when r.busy => l.ofBusyWithAnother,
    final r => batchSummary(l, r),
  }, kind: result == null || result.busy ? ToastKind.warn : ToastKind.success);
}

/// Saves a file where it's seen outside Bloom (shared Music/Bloom on Android,
/// the app's folder in Files on iOS).
Future<void> saveTrackFile(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  Track track,
) async {
  final toast = messenger.busyToast(l.ofDownloadingTrack);
  try {
    final path = await saveTrackAsFile(ref, track);
    toast.finish(l.ofSaved(path ?? saveTargetLabel(l)));
  } catch (e) {
    toast.finish(
      describeSaveError(l, readableSaveError(e)),
      kind: ToastKind.error,
    );
  }
}

/// Save the cover as a picture.
Future<void> saveCoverFile(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  Track track,
) async {
  final toast = messenger.busyToast(l.fdDownloadingCover);
  try {
    final path = await saveCoverAsFile(track);
    toast.finish(
      l.ofSaved(path ?? saveTargetLabel(l)),
      kind: ToastKind.success,
    );
  } catch (e) {
    toast.finish(
      describeSaveError(l, readableSaveError(e)),
      kind: ToastKind.error,
    );
  }
}

/// Saves a whole list as files.
Future<void> saveListFiles(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  String sourceId,
  List<Track> tracks,
) async {
  // The same batch indicator as offline copies (see `beginBatch`), so the same
  // toast.
  final toast = messenger.busyToast(
    l.ofDownloadingFiles,
    content: (view) => BatchToastBody(view: view),
  );
  final result = await saveListAsFiles(ref, sourceId, tracks);
  toast.finish(
    result.total == 0
        ? l.ofNothingToDownload
        : batchSummary(
            l,
            BatchResult(total: result.total, failed: result.failed),
          ),
    kind: result.total == 0
        ? ToastKind.warn
        : result.failed == 0
        ? ToastKind.success
        : ToastKind.warn,
  );
}

/// Removes offline copies of all the list's tracks.
Future<void> removeListOffline(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final n = await ref.read(offlineProvider.notifier).removeAll(tracks);
  messenger.toast(
    n == 0 ? l.ofNoCopies : l.ofRemovedCount(n),
    kind: n == 0 ? ToastKind.warn : ToastKind.info,
  );
}

/// A list's offline state: how many of its downloadable tracks are on the
/// device. State comes as an argument rather than read inside: it's called from
/// `build` (needing `watch`, so the tag updates as it loads) and from a sheet's
/// handler (only `read`).
({bool any, bool all, int cached, int total}) listOfflineState(
  OfflineState state,
  OfflineController offline,
  List<Track> tracks,
) {
  final downloadable = tracks.where(offline.canDownload).toList();
  final cached = downloadable.where((t) => state.has(t.id)).length;
  return (
    any: cached > 0,
    all: downloadable.isNotEmpty && cached == downloadable.length,
    cached: cached,
    total: downloadable.length,
  );
}

/// Batch download toast body: an N/M count, a progress bar below instead of a
/// countdown, and Stop. A toast, so progress shows from any screen. The store
/// has one batch per app, so there's no `sourceId` to check: a running batch is
/// ours.
class BatchToastBody extends ConsumerWidget {
  const BatchToastBody({super.key, required this.view});

  /// Toast state from [ToastHandle]: before `finish()` work is under way, after
  /// it the result, and the batch count no longer matters.
  final ValueListenable<ToastView> view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(offlineProvider.select((s) => s.batch));

    return ValueListenableBuilder(
      valueListenable: view,
      builder: (_, v, _) {
        final live = v.busy && batch != null;
        return BloomToastCard(
          text: live
              ? context.l.ofSavingProgress(batch.done, batch.total)
              : v.text,
          kind: v.kind,
          busy: v.busy,
          progress: live && batch.total > 0 ? batch.done / batch.total : null,
          barDuration: v.barDuration,
          actionLabel: live ? context.l.ofAbort : null,
          onAction: live
              ? () => ref.read(offlineProvider.notifier).cancelBatch()
              : null,
        );
      },
    );
  }
}

/// A refusal's reason as a phrase. Here rather than in the store: only the UI
/// has the language.
String describeOfflineFailure(AppLocalizations l, OfflineFailure failure) =>
    switch (failure.kind) {
      OfflineFailureKind.noStorage => l.ofNoStorage,
      OfflineFailureKind.notSavable => l.ofCantSaveTrack,
      OfflineFailureKind.streamOnly => l.ofStreamOnly,
      OfflineFailureKind.drm => l.ofDrm,
      OfflineFailureKind.noFileLink => l.ofNoFileLink,
      OfflineFailureKind.noConnection => l.ofNoConnection,
      OfflineFailureKind.unknown => l.ofSaveFailed(failure.detail ?? ''),
    };

/// The same for saving a file.
String describeSaveError(AppLocalizations l, DownloadFailure failure) =>
    switch (failure.kind) {
      DownloadFailureKind.notDownloadable => l.fdCantDownload,
      DownloadFailureKind.needPermission => l.fdNeedPermission,
      DownloadFailureKind.noConnection => l.ofNoConnection,
      DownloadFailureKind.unknown => failure.detail ?? l.fdSaveFailed,
    };

/// A batch's result as a phrase.
String batchSummary(AppLocalizations l, BatchResult r) {
  if (r.failed == 0) return l.ofDownloadedAll(r.ok);
  if (r.ok == 0) return l.ofDownloadedNone;
  return l.ofDownloadedPartial(r.ok, r.total, r.failed);
}
