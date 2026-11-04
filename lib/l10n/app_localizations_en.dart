// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonBack => 'Back';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDone => 'Done';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonUpload => 'Upload';

  @override
  String get commonHide => 'Hide';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonOr => 'or';

  @override
  String get commonPin => 'Pin';

  @override
  String get commonUnpin => 'Unpin';

  @override
  String get commonPlay => 'Play';

  @override
  String get commonPause => 'Pause';

  @override
  String get commonShuffle => 'Shuffle';

  @override
  String get commonFollow => 'Follow';

  @override
  String get commonUnfollow => 'Unfollow';

  @override
  String get commonLoadMore => 'Load more';

  @override
  String get commonAlbum => 'Album';

  @override
  String get commonPlaylist => 'Playlist';

  @override
  String get commonArtist => 'Artist';

  @override
  String get commonProfile => 'Profile';

  @override
  String get commonTracks => 'Tracks';

  @override
  String get commonPlaylists => 'Playlists';

  @override
  String get commonAlbums => 'Albums';

  @override
  String get commonArtists => 'Artists';

  @override
  String get commonAllTracks => 'All tracks';

  @override
  String get commonFavorites => 'Liked';

  @override
  String get commonHistory => 'History';

  @override
  String get commonNewPlaylist => 'New playlist';

  @override
  String get commonCreatePlaylist => 'Create playlist';

  @override
  String get commonAddToLibrary => 'Add to library';

  @override
  String get commonAlreadyInLibrary => 'Already in your library';

  @override
  String get commonUnknownArtist => 'Unknown';

  @override
  String get commonUntitled => 'Untitled';

  @override
  String get commonOfflineBadge => 'offline';

  @override
  String get commonAddedOn => 'Added';

  @override
  String get commonCreatedOn => 'Created';

  @override
  String commonDurHm(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String commonDurMin(int m) {
    return '$m min';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '$count track',
    );
    return '$_temp0';
  }

  @override
  String playsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plays',
      one: '$count play',
    );
    return '$_temp0';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get navSearch => 'Search';

  @override
  String get sourceLocal => 'Local';

  @override
  String get sourceYandex => 'Yandex Music';

  @override
  String get homeCharts => 'Chart';

  @override
  String get homeNewReleases => 'Releases';

  @override
  String chartUp(int n) {
    return 'Up $n';
  }

  @override
  String chartDown(int n) {
    return 'Down $n';
  }

  @override
  String get chartSame => 'No change';

  @override
  String get chartNew => 'New entry';

  @override
  String get chartNewShort => 'new';

  @override
  String get relAlbum => 'album';

  @override
  String get relSingle => 'single';

  @override
  String get relCompilation => 'compilation';

  @override
  String get relPodcast => 'podcast';

  @override
  String get relEp => 'EP';

  @override
  String get homeForYou => 'For you';

  @override
  String get homeForYouAll => 'All picks';

  @override
  String get homeSimilarTo => 'Similar to';

  @override
  String get playerQueue => 'Queue';

  @override
  String get queueSecPlayed => 'Played';

  @override
  String get queueSecNow => 'Now playing';

  @override
  String get queueSecNext => 'Up next';

  @override
  String playerNextUp(String title) {
    return 'Up next: $title';
  }

  @override
  String playerSourceSearch(String query) {
    return 'Search: $query';
  }

  @override
  String get playerCopied => 'Copied';

  @override
  String get playerCopyError => 'Error';

  @override
  String get playerSpeed => 'Speed';

  @override
  String get playerSpeedCustom => 'Custom speed';

  @override
  String get playerSpeedReset => 'Reset to 1×';

  @override
  String get playerSpeedNightcore => 'Nightcore';

  @override
  String get playerSleep => 'Sleep timer';

  @override
  String playerSleepMinutes(int count) {
    return '$count min';
  }

  @override
  String playerSleepLeft(String time) {
    return '$time left';
  }

  @override
  String get playerSleepEndOfTrack => 'Until end of track';

  @override
  String get playerSleepCustom => 'Custom time';

  @override
  String get playerSleepExtend => '+5 minutes';

  @override
  String get playerSleepCancel => 'Turn off timer';

  @override
  String get playerSleepFade => 'Fade out';

  @override
  String get notifChannelName => 'Playback';

  @override
  String get notifChannelDescription =>
      'Music controls in the notification shade and on the lock screen';

  @override
  String get artistSourceNotConnected => 'This artist’s source isn’t connected';

  @override
  String get artistNotFound => 'Artist not found';

  @override
  String get artistPopular => 'Popular';

  @override
  String get artistSimilar => 'Fans might also like';

  @override
  String get artistNoTracks => 'This artist has no available tracks';

  @override
  String get artistAbout => 'About';

  @override
  String get artistAboutProfile => 'About';

  @override
  String get artistLikes => 'Likes';

  @override
  String get artistShowAll => 'Show all';

  @override
  String get artistImport => 'Import';

  @override
  String get artistImportLoading => 'Loading the artist’s tracks…';

  @override
  String get artistLikesLoading => 'Loading all of the likes…';

  @override
  String likesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count likes',
      one: '$count like',
    );
    return '$_temp0';
  }

  @override
  String get artistNotFoundOnSource => 'Not found on the source';

  @override
  String followedToast(String name) {
    return 'Following $name';
  }

  @override
  String get unfollowedToast => 'Unfollowed';

  @override
  String addedToast(String title, String tracks) {
    return 'Added: $title — $tracks';
  }

  @override
  String get setSourceNotConnected => 'This list’s source isn’t connected';

  @override
  String get setAlbumNotFound => 'Album not found';

  @override
  String get setPlaylistNotFound => 'Playlist not found';

  @override
  String get setNoTracks => 'No tracks available';

  @override
  String get libTabAll => 'All';

  @override
  String get libTabArtists => 'Artists';

  @override
  String get libSystem => 'System';

  @override
  String get libAllTracksSub => 'The whole library';

  @override
  String get libLikedSub => 'Liked tracks';

  @override
  String get libNoTracks => 'No tracks';

  @override
  String get libAutoRefreshTooltip => 'Playlist auto-refresh';

  @override
  String get libSortManual => 'Default';

  @override
  String get libSortNameAsc => 'By name A–Z';

  @override
  String get libSortNameDesc => 'By name Z–A';

  @override
  String get tlSortManual => 'In order';

  @override
  String get tlSortName => 'By title';

  @override
  String get tlSortArtist => 'By artist';

  @override
  String get tlSortAlbum => 'By album';

  @override
  String get tlSortDuration => 'By length';

  @override
  String get tlSortDate => 'By date added';

  @override
  String get tlSortPlays => 'By plays';

  @override
  String get tlSortDownloaded => 'Downloaded only';

  @override
  String get tlSortNotDownloaded => 'Not downloaded only';

  @override
  String get tlNothingFound => 'Nothing found';

  @override
  String get tlNothingDownloaded => 'Nothing downloaded here';

  @override
  String get tlNothingNotDownloaded => 'Everything here is downloaded';

  @override
  String get tlEmptyFav => 'Nothing liked yet';

  @override
  String get histToday => 'Today';

  @override
  String get histYesterday => 'Yesterday';

  @override
  String histDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '$count day ago',
    );
    return '$_temp0';
  }

  @override
  String get histWeekAgo => 'A week ago';

  @override
  String get tlEmptyAll => 'Your library is empty';

  @override
  String get tlEmptyPlaylist => 'This playlist is empty';

  @override
  String get tlSearchHint => 'In this list';

  @override
  String get tlJumpToNow => 'Now playing';

  @override
  String get tlStopSaving => 'Stop saving';

  @override
  String get tlRemoveOffline => 'Remove from offline';

  @override
  String tlListenOffline(int count) {
    return 'Listen offline ($count)';
  }

  @override
  String tlDownloadFiles(int count) {
    return 'Download as files ($count)';
  }

  @override
  String get tlRefreshTracks => 'Refresh tracks';

  @override
  String get tlToQueue => 'Add to queue';

  @override
  String get tlPlayNext => 'Play next';

  @override
  String tlQueuedTracks(int count) {
    return 'Added to queue: $count';
  }

  @override
  String tlQueuedNext(int count) {
    return 'Playing next: $count';
  }

  @override
  String get tlExportPlaylist => 'Export playlist';

  @override
  String get tlDeletePlaylist => 'Delete playlist';

  @override
  String tlPlaylistDeleted(String name) {
    return '“$name” deleted';
  }

  @override
  String get tlDeletePlaylistWithTracks => 'Delete playlist and tracks';

  @override
  String get tlPlaylistAndTracksDeleted => 'Deleted with tracks';

  @override
  String leAddedToFavorites(String tracks) {
    return 'Liked: $tracks';
  }

  @override
  String leRemovedFromFavorites(String tracks) {
    return 'Unliked: $tracks';
  }

  @override
  String leDeleteArm(String tracks) {
    return 'Tap again: delete $tracks';
  }

  @override
  String get leDiscardArm => 'Tap again to discard';

  @override
  String cpImported(String title, int count) {
    return 'Imported: $title — $count';
  }

  @override
  String get cpAllAlreadyIn => 'Already in your library';

  @override
  String cpAdded(int count) {
    return 'Added: $count';
  }

  @override
  String get cpSourceNoAnswer => 'The source didn’t respond';

  @override
  String get cpNameHint => 'My playlist';

  @override
  String get cpImport => 'Import';

  @override
  String get cpLinkHint => 'Paste a link…';

  @override
  String get cpFromFile => 'From file';

  @override
  String cpDestination(String target) {
    return 'To: $target';
  }

  @override
  String paEveryMinutes(int count) {
    return '$count min';
  }

  @override
  String paEveryHours(int count) {
    return '$count h';
  }

  @override
  String get paJustNow => 'just now';

  @override
  String paMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String paHoursAgo(int count) {
    return '$count h ago';
  }

  @override
  String paDaysAgo(int count) {
    return '$count d ago';
  }

  @override
  String get paTitle => 'Auto-refresh';

  @override
  String get paOff => 'Off';

  @override
  String get paNoneSelected => 'Nothing selected';

  @override
  String get paOnStartTitle => 'Check on launch';

  @override
  String get paPlaylistsWithSources => 'Playlists with sources';

  @override
  String get paSelectAll => 'Select all';

  @override
  String get paNothingToRefresh =>
      'Nothing to refresh: no playlist has sources yet. Link one while editing a playlist — or import a playlist from a link and it remembers its own.';

  @override
  String get paRefreshing => 'Refreshing…';

  @override
  String get paSoon => 'any moment';

  @override
  String paNextIn(String time) {
    return 'in $time';
  }

  @override
  String paSelected(int selected, int total) {
    return 'Selected: $selected of $total';
  }

  @override
  String get paPeriod => 'Frequency';

  @override
  String get paRunUpdating => 'refreshing…';

  @override
  String get paRunError => 'error';

  @override
  String get paRunNoChanges => 'no changes';

  @override
  String get paRefreshNow => 'Refresh now';

  @override
  String paBusy(int count) {
    return 'Refreshing $count…';
  }

  @override
  String paProgress(int done, int total) {
    return 'Refreshing: $done/$total';
  }

  @override
  String paNewTracks(int added) {
    return 'New tracks: $added';
  }

  @override
  String paFailed(int count) {
    return 'Not refreshed: $count';
  }

  @override
  String get paNoNewTracks => 'No new tracks';

  @override
  String rpBusy(String name) {
    return 'Refreshing “$name”…';
  }

  @override
  String get rpNoAnswer => 'The source didn’t respond';

  @override
  String rpNewTracks(int count) {
    return 'New tracks: $count';
  }

  @override
  String get psTitle => 'Update sources';

  @override
  String get psHint =>
      'Link playlists, albums or likes from any platform — “Refresh tracks” will add new tracks from them to the top of this playlist.';

  @override
  String get psAddHint => 'Paste a playlist, album or profile link…';

  @override
  String get psRemove => 'Unlink';

  @override
  String get psDuplicate => 'Source already linked';

  @override
  String get iuUnrecognized => 'Couldn’t make sense of that link';

  @override
  String iuLikesTitle(String name) {
    return 'Likes · $name';
  }

  @override
  String get iuOnlySupported => 'Only playlist, album or likes';

  @override
  String get iuNoTracks => 'That link has no tracks';

  @override
  String get iuPlaylistGone => 'That playlist no longer exists';

  @override
  String get ofRemoved => 'Removed from offline';

  @override
  String get ofSaving => 'Saving for offline…';

  @override
  String ofAvailable(String name) {
    return 'Available offline: $name';
  }

  @override
  String get ofNothingToSave => 'Nothing to save offline';

  @override
  String get ofDownloadingTrack => 'Downloading track…';

  @override
  String ofSaved(String path) {
    return 'Saved: $path';
  }

  @override
  String get ofDownloadingFiles => 'Downloading files…';

  @override
  String get ofNothingToDownload => 'Nothing here to download';

  @override
  String get ofNoCopies => 'There were no offline copies';

  @override
  String ofRemovedCount(int count) {
    return 'Removed from offline: $count';
  }

  @override
  String get ofAbort => 'Stop';

  @override
  String get ofNoStorage => 'No access to storage';

  @override
  String get ofCantSaveTrack => 'This track can’t be saved';

  @override
  String get ofBusyWithAnother => 'Already downloading a list';

  @override
  String ofDownloadedAll(int count) {
    return 'Tracks downloaded: $count';
  }

  @override
  String get ofDownloadedNone => 'Nothing downloaded';

  @override
  String ofDownloadedPartial(int ok, int total, int failed) {
    return 'Got $ok/$total, failed: $failed';
  }

  @override
  String get ofStreamOnly => 'Stream-only, can’t be saved';

  @override
  String get ofDrm => 'The track is DRM-protected';

  @override
  String get ofNoFileLink => 'No file link from the source';

  @override
  String get ofNoConnection => 'No connection';

  @override
  String ofSaveFailed(String message) {
    return 'Couldn’t save: $message';
  }

  @override
  String get fdPathIos => 'Files → On My iPhone → Bloom';

  @override
  String get fdPathAndroid => 'Music/Bloom';

  @override
  String get fdCantDownload => 'Can’t download this track';

  @override
  String get fdNeedPermission => 'Storage access needed';

  @override
  String get fdSaveFailed => 'Couldn’t save the file';

  @override
  String get fdDownloadFile => 'Download as a file';

  @override
  String get fdDownloadCover => 'Download cover';

  @override
  String get fdDownloadingCover => 'Downloading cover…';

  @override
  String get tlConvert => 'Transfer to source…';

  @override
  String get cvTitle => 'Transfer to source';

  @override
  String cvScanning(String source) {
    return 'Looking up tracks on $source…';
  }

  @override
  String get cvScanHint => 'You can leave — the transfer will be cancelled';

  @override
  String cvSummary(int moved, int kept, int skipped) {
    return 'Moved $moved · kept $kept · skipped $skipped';
  }

  @override
  String get cvTakeBest => 'Take the best';

  @override
  String cvCreate(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Create a playlist of $count tracks',
      one: 'Create a playlist of $count track',
    );
    return '$_temp0';
  }

  @override
  String get cvTagMoved => 'Transferred';

  @override
  String get cvTagOriginal => 'Original';

  @override
  String get cvTagOnTarget => 'Already here';

  @override
  String get cvTagSkipped => 'Skipped';

  @override
  String cvNotFound(String source) {
    return 'Not found on $source';
  }

  @override
  String get cvSearchFailed => 'The source didn’t answer';

  @override
  String get cvKeepOriginal => 'Keep the original';

  @override
  String get cvSkip => 'Skip this track';

  @override
  String cvCreated(String name, String tracks) {
    return '“$name” created — $tracks';
  }

  @override
  String get spSwitch => 'Switch source';

  @override
  String spSearching(String source) {
    return 'Looking on $source…';
  }

  @override
  String spNow(String source) {
    return 'Now playing from $source';
  }

  @override
  String spNotFound(String source) {
    return 'This track isn’t on $source';
  }

  @override
  String get spFailed => 'The source didn’t answer';

  @override
  String get spUnavailable => 'This source is unavailable';

  @override
  String get tlMergeWith => 'Merge with…';

  @override
  String get mgTitle => 'Merging playlists';

  @override
  String get mgNameHint => 'Name of the new playlist';

  @override
  String get mgPickHint => 'Pick what to merge in';

  @override
  String mgResult(String tracks) {
    return 'You’ll get $tracks';
  }

  @override
  String mgDupsDropped(int count) {
    return '−$count repeats';
  }

  @override
  String get mgDedup => 'Remove duplicates';

  @override
  String get mgDeleteSources => 'Delete the originals';

  @override
  String get mgNothingToMerge => 'No other playlists';

  @override
  String mgMerged(String name, String tracks) {
    return '“$name” collected — $tracks';
  }

  @override
  String get tlFindDups => 'Find duplicates';

  @override
  String get dupsTitle => 'Duplicate tracks';

  @override
  String dupsFound(int groups, int extra) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups groups',
      one: '$groups group',
    );
    String _temp1 = intl.Intl.pluralLogic(
      extra,
      locale: localeName,
      other: '$extra extra copies',
      one: '$extra extra copy',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String dupsChecked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks checked',
      one: '$count track checked',
    );
    return '$_temp0';
  }

  @override
  String dupsCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count copies',
      one: '$count copy',
    );
    return '$_temp0';
  }

  @override
  String dupsPlays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plays',
      one: '$count play',
    );
    return '$_temp0';
  }

  @override
  String get dupsKeep => 'keep';

  @override
  String get dupsNone => 'No duplicates found';

  @override
  String get dupsDelAll => 'Remove all';

  @override
  String get dupsDelGroup => 'Remove copies';

  @override
  String dupsRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count copies removed',
      one: '$count copy removed',
    );
    return '$_temp0';
  }

  @override
  String get tiTitle => 'Track info';

  @override
  String get tiAlbum => 'Album';

  @override
  String get tiYear => 'Year';

  @override
  String get tiReleased => 'Release date';

  @override
  String get setRelease => 'Release';

  @override
  String get tiDuration => 'Duration';

  @override
  String get tiPublisher => 'Publisher';

  @override
  String get tiGenres => 'Genres';

  @override
  String get tiDescription => 'Description';

  @override
  String get tiFile => 'File';

  @override
  String get tiCredited => 'Credited';

  @override
  String get tiExplicit => 'Explicit lyrics';

  @override
  String get tiNothing =>
      'The source didn’t share anything else about this track';

  @override
  String get taToQueue => 'To queue';

  @override
  String get taPlayNext => 'Play next';

  @override
  String get taRemoveFromQueue => 'Remove from queue';

  @override
  String get taRemoveFromPlaylist => 'Remove from playlist';

  @override
  String get taDownload => 'Download';

  @override
  String get taRemoveFromFavorites => 'Remove from likes';

  @override
  String get taAddToFavorites => 'Like';

  @override
  String get taAddToPlaylist => 'Add to playlist';

  @override
  String get taListenOffline => 'Listen offline';

  @override
  String get taRemoveOffline => 'Remove from offline';

  @override
  String get taGoToArtist => 'Go to artist';

  @override
  String get taDeleteTrack => 'Delete track';

  @override
  String get taTrackDeleted => 'Track deleted';

  @override
  String get taAddedToLibrary => 'Added to library';

  @override
  String get searchTabAll => 'Everything';

  @override
  String get searchHint => 'Search';

  @override
  String get searchSourceAll => 'All sources';

  @override
  String get searchNothingFound => 'Nothing found';

  @override
  String get searchSectionEmpty => 'Nothing found in this section';

  @override
  String get profileDefaultName => 'Listener';

  @override
  String get profileNickCopied => 'Nickname copied!';

  @override
  String get profileAchievements => 'Achievements';

  @override
  String get profileSaved => 'Profile saved!';

  @override
  String get profileNickname => 'NICKNAME';

  @override
  String get profileNicknameHint => 'Enter a nickname...';

  @override
  String get profileAbout => 'ABOUT';

  @override
  String get profileAboutHint => 'Tell us about yourself...';

  @override
  String get profileStatus => 'STATUS';

  @override
  String get profileStatusHint => '\"My status...\"';

  @override
  String get profileColorSolid => 'Color';

  @override
  String get profileColorAuto => 'Auto';

  @override
  String get profileColorGradient => 'Gradient';

  @override
  String get profileAutoHint => 'The colour of your most played track\'s cover';

  @override
  String profileSince(String date) {
    return 'With us since $date';
  }

  @override
  String profileSumPlays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'plays',
      one: 'play',
    );
    return '$_temp0';
  }

  @override
  String get profileSumTime => 'listened';

  @override
  String profileSumStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days in a row',
      one: 'day in a row',
    );
    return '$_temp0';
  }

  @override
  String profileSumArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'artists',
      one: 'artist',
    );
    return '$_temp0';
  }

  @override
  String get profileEntryStats => 'Statistics';

  @override
  String profileEntryOf(int total) {
    return 'of $total';
  }

  @override
  String get profileActivityDays => 'last 30 days';

  @override
  String get historyEmpty => 'Tracks you listen to will show up here';

  @override
  String get profileRemoveImage => 'Remove image';

  @override
  String get profileRemovePhoto => 'Remove photo';

  @override
  String profileZoom(int percent) {
    return 'Zoom  $percent%';
  }

  @override
  String achUnlockedToast(String name, String tier) {
    return '🏅 $name — $tier';
  }

  @override
  String get achMax => 'Maxed out';

  @override
  String achUnlockedAt(String date) {
    return 'earned $date';
  }

  @override
  String get achTierBronze => 'Bronze';

  @override
  String get achTierSilver => 'Silver';

  @override
  String get achTierGold => 'Gold';

  @override
  String get achListenerName => 'Music Lover';

  @override
  String get achListenerDesc => 'Total plays';

  @override
  String get achTimeName => 'In the Headphones';

  @override
  String get achTimeDesc => 'Listening time';

  @override
  String get achStreakName => 'On a Roll';

  @override
  String get achStreakDesc => 'Days in a row with plays';

  @override
  String get achMarathonName => 'Marathoner';

  @override
  String get achMarathonDesc => 'Tracks in a single day';

  @override
  String get achVeteranName => 'Bloom Veteran';

  @override
  String get achVeteranDesc => 'Time in the app';

  @override
  String get achDevoteeName => 'Devotion';

  @override
  String get achDevoteeDesc => 'Active days total';

  @override
  String get statsTracks => 'Tracks';

  @override
  String get statsPlays => 'Plays';

  @override
  String get statsTime => 'Listening time';

  @override
  String get statsUnique => 'Unique';

  @override
  String get statsAvgLength => 'Average length';

  @override
  String get statsFavArtist => 'Favorite artist';

  @override
  String get statsAppTime => 'Time in app';

  @override
  String get statsRecordDay => 'Day record';

  @override
  String get statsHoursDay => 'hours/day';

  @override
  String get statsTracksDay => 'tracks/day';

  @override
  String get statsArtists => 'artists';

  @override
  String get statsSources => 'Where you listen most';

  @override
  String get statsTopTracks => 'Top tracks';

  @override
  String get statsTopArtists => 'Top artists';

  @override
  String get statsOverview => 'Overview';

  @override
  String get statsNoDataYet => 'No data yet';

  @override
  String get statsCopy => 'Copy';

  @override
  String get statsClear => 'Clear';

  @override
  String get statsClearTitle => 'Clear the statistics?';

  @override
  String get statsClearSub =>
      'Plays, history, activity and achievements will be deleted';

  @override
  String get statsClearLevel => 'Reset the level too';

  @override
  String levelTitle(int level) {
    return 'Level $level';
  }

  @override
  String get levelDesc =>
      'Your level grows as you listen to music and come back to Bloom';

  @override
  String levelXp(String into, String span) {
    return '$into / $span XP';
  }

  @override
  String levelToNext(int level, String xp) {
    return '$xp XP to level $level';
  }

  @override
  String levelTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $count tracks',
      one: '≈ $count track',
    );
    return '$_temp0';
  }

  @override
  String get levelHow => 'How it grows';

  @override
  String get levelPlays => 'Listening';

  @override
  String levelPlaysSub(int xp) {
    return '+$xp XP a track';
  }

  @override
  String get levelDays => 'Daily visits';

  @override
  String levelDaysSub(int xp) {
    return '+$xp XP a day, more for days in a row';
  }

  @override
  String get levelAch => 'Achievements';

  @override
  String levelAchSub(int bronze, int silver, int gold) {
    return '+$bronze / $silver / $gold XP for bronze, silver and gold';
  }

  @override
  String get levelBanked => 'Earlier stats';

  @override
  String get levelBankedSub => 'Kept when the stats were cleared';

  @override
  String get levelOk => 'Got it';

  @override
  String get statsCopied => 'Statistics copied';

  @override
  String get statsCleared => 'Statistics cleared';

  @override
  String get statsZeroMinutes => '0 min';

  @override
  String statsHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String statsMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get statsShareTitle => '🎵 My Bloom stats';

  @override
  String statsShareTracks(int count) {
    return '📚 Tracks: $count';
  }

  @override
  String statsShareUnique(int count) {
    return '🎵 Unique: $count';
  }

  @override
  String statsSharePlays(int count) {
    return '▶️ Played: $count';
  }

  @override
  String statsShareTime(String value) {
    return '🎧 Listening time: $value';
  }

  @override
  String statsShareAvgLength(String value) {
    return '📏 Average length: $value';
  }

  @override
  String statsShareAppTime(String value) {
    return '⏱️ Time in app: $value';
  }

  @override
  String statsShareFavArtist(String name) {
    return '⭐ Favorite artist: $name';
  }

  @override
  String statsShareRecordDay(int count) {
    return '🏆 Day record: $count';
  }

  @override
  String get statsShareAvgPerDay => '📈 Daily average:';

  @override
  String get statsShareSources => '📡 Where you listened most:';

  @override
  String get statsShareTopTracks => '🔥 Top tracks:';

  @override
  String get statsShareTopArtists => '👤 Top artists:';

  @override
  String get setGroupApp => 'APP';

  @override
  String get setGroupInterface => 'INTERFACE';

  @override
  String get setGroupIntegrations => 'INTEGRATIONS';

  @override
  String get setSystem => 'System';

  @override
  String get setAudio => 'Audio';

  @override
  String get setSwipes => 'Swipes';

  @override
  String get setLanguage => 'Language';

  @override
  String get setStorage => 'Storage';

  @override
  String get setPlayer => 'Player';

  @override
  String get setAppearance => 'Appearance';

  @override
  String get setMiniPlayer => 'Mini player';

  @override
  String get pvGroupTitle => 'Title';

  @override
  String get pvTitleAlignLeft => 'Left';

  @override
  String get pvTitleAlignCenter => 'Center';

  @override
  String get pvTitleAlignRight => 'Right';

  @override
  String get pvStyleRow => 'Player style';

  @override
  String get pvStyleStandard => 'Standard';

  @override
  String get pvStyleVinyl => 'Vinyl';

  @override
  String get pvPlayButtonRow => 'Play button';

  @override
  String get pvPlayButtonCircle => 'Circle';

  @override
  String get pvPlayButtonSquare => 'Square';

  @override
  String get pvPlayButtonPlain => 'No background';

  @override
  String get pvGroupSlider => 'Slider';

  @override
  String get pvSliderStandard => 'Standard';

  @override
  String get pvSliderThin => 'Thin';

  @override
  String get pvSliderWave => 'Wave';

  @override
  String get pvGroupLyrics => 'Lyrics';

  @override
  String get pvLyricsModeOverlay => 'Over the cover';

  @override
  String get pvLyricsModeReplace => 'Instead of the cover';

  @override
  String get pvGroupQueue => 'Queue';

  @override
  String get pvQueueNormal => 'Normal';

  @override
  String get pvQueueExtended => 'Extended';

  @override
  String get pvNextUp => 'Next track';

  @override
  String get pvNextUpSub => 'A pill under the slider with what plays next';

  @override
  String get pvGroupBg => 'Player background';

  @override
  String get pvBgRow => 'Player background';

  @override
  String get pvBgCover => 'Cover';

  @override
  String get pvBgCoverSub => 'The track cover, full screen';

  @override
  String get pvBgApp => 'App background';

  @override
  String get pvBgAppSub => 'The picture set as the app background';

  @override
  String get pvBgAppOff =>
      'Set a picture as the background in Customization first';

  @override
  String get pvBgColor => 'Color';

  @override
  String get pvBgColorSub => 'Adaptive gradient from the cover';

  @override
  String get pvBgNone => 'None';

  @override
  String get pvBgNoneSub => 'No background';

  @override
  String get pvBgFxDim => 'Dim';

  @override
  String get pvBgFxBlur => 'Blur';

  @override
  String get pvBgFxOriginal => 'Original';

  @override
  String get pvGroupMiniControls => 'Controls';

  @override
  String get pvMiniBgRow => 'Background';

  @override
  String get pvMiniBgTheme => 'Standard';

  @override
  String get pvMiniBgCoverColor => 'Color';

  @override
  String get pvMiniBgCover => 'Cover';

  @override
  String get pvMiniProgressRow => 'Progress indicators';

  @override
  String get pvMiniProgressLine => 'Line';

  @override
  String get pvMiniProgressFill => 'Fill';

  @override
  String get pvMiniProgressRing => 'Ring';

  @override
  String get pvMiniProgressTint => 'Track color';

  @override
  String get pvMiniProgressTintSub =>
      'Color the progress with the cover accent instead of the theme color';

  @override
  String get pvMiniShapeRow => 'Cover shape';

  @override
  String get pvMiniShapeRounded => 'Rounded';

  @override
  String get pvMiniShapeCircle => 'Circle';

  @override
  String get pvMiniRadiusRow => 'Corner rounding';

  @override
  String get pvMiniRadiusNone => 'None';

  @override
  String get pvMiniRadiusSoft => 'Soft';

  @override
  String get pvMiniRadiusRounded => 'Rounded';

  @override
  String get pvMiniRadiusPill => 'Pill';

  @override
  String get pvMiniButtonsRow => 'Controls';

  @override
  String get pvMiniButtonsSub => 'what stands in the row right of the title';

  @override
  String get pvMiniButtonsNone => 'None';

  @override
  String get pvMiniButtonPrev => 'Previous';

  @override
  String get pvMiniButtonPlay => 'Play/Pause';

  @override
  String get pvMiniButtonNext => 'Next';

  @override
  String get pvMiniButtonFav => 'Like';

  @override
  String get pvMiniNeighborsRow => 'Adjacent tracks';

  @override
  String get pvMiniNeighborsOff => 'Hidden';

  @override
  String get pvMiniNeighborsOn => 'At the edges';

  @override
  String get lyricsLoading => 'Loading lyrics…';

  @override
  String get lyricsNotFound => 'Lyrics not found';

  @override
  String get swZoneLibrary => 'Library';

  @override
  String get swZoneQueue => 'Queue';

  @override
  String get swZoneMini => 'Mini player';

  @override
  String get swZonePlayer => 'Player';

  @override
  String get swLeft => 'Swipe left';

  @override
  String get swRight => 'Swipe right';

  @override
  String get swActNone => 'Disabled';

  @override
  String get swActLike => 'Like';

  @override
  String get swActQueue => 'Add to queue';

  @override
  String get swActPlayNext => 'Play next';

  @override
  String get swActNext => 'Next';

  @override
  String get swActPrev => 'Previous';

  @override
  String get swActDownload => 'Download';

  @override
  String get swActDelete => 'Delete';

  @override
  String get swAddedToQueue => 'Added to queue';

  @override
  String get swAlreadyInQueue => 'Already in the queue';

  @override
  String get swPlaysNext => 'Plays next';

  @override
  String get swLiked => 'Added to favorites';

  @override
  String get swUnliked => 'Removed from favorites';

  @override
  String get swRemoved => 'Removed';

  @override
  String get apLanguageRu => 'Русский';

  @override
  String get apLanguageEn => 'English';

  @override
  String get apTheme => 'THEME';

  @override
  String get apThemeRow => 'Theme';

  @override
  String get thNew => 'Custom theme';

  @override
  String get thNameDefault => 'My theme';

  @override
  String get thSlotBg => 'Background';

  @override
  String get thSlotCard => 'Card';

  @override
  String get thSlotAccent => 'Accent';

  @override
  String get thRandom => 'Random colors';

  @override
  String thCreated(String name) {
    return 'Theme “$name” created';
  }

  @override
  String get thDeleted => 'Preset deleted';

  @override
  String get thAutoName => 'Auto theme';

  @override
  String get thAutoCard => 'Match track cover';

  @override
  String get apAutoAccent => 'Auto accent';

  @override
  String get apAutoAccentSub => 'Accent color from the track cover';

  @override
  String get apAutoAccentLevel => 'Accent brightness';

  @override
  String get apBgGroup => 'BACKGROUND';

  @override
  String get apBadgesTitle => 'Badges in accent color';

  @override
  String get apBadgesSubtitle =>
      'Source badges use their brand colors by default; enable to tint them with the accent';

  @override
  String get apNavBar => 'TAB BAR';

  @override
  String get apNavBarRow => 'Tab bar';

  @override
  String get apNavBarPlain => 'Standard';

  @override
  String get apNavBarRounded => 'Rounded top';

  @override
  String get apNavBarDome => 'Dome';

  @override
  String get apNavBarFloating => 'Floating';

  @override
  String get apNavBarPill => 'Pill';

  @override
  String get apNavTabsRow => 'Tab order';

  @override
  String get apNavTabsDrag =>
      'Drag a tab by its handle to change its place in the bar';

  @override
  String get apNavMarkRow => 'Active tab mark';

  @override
  String get apNavMarkNone => 'None';

  @override
  String get apNavMarkPill => 'Pill';

  @override
  String get apNavMarkDot => 'Dot';

  @override
  String get apNavMarkLine => 'Line';

  @override
  String get apNavLabelsRow => 'Labels';

  @override
  String get apNavLabelsNone => 'None';

  @override
  String get apNavLabelsAlways => 'Always';

  @override
  String get apNavLabelsActive => 'Active only';

  @override
  String get apNavHomeLogoRow => 'Logo instead of Home';

  @override
  String get apNavHomeLogoSub =>
      'Show the Bloom mark in place of the Home tab icon';

  @override
  String get scHelp =>
      'Usually not needed: the key is picked up automatically — by scraping the site, and failing that by trying known ones. Setting your own makes sense if SoundCloud stopped responding.';

  @override
  String get scHint => 'Automatic';

  @override
  String get scCheckConnection => 'Check connection';

  @override
  String get scConnectionOk => 'Connection works';

  @override
  String get scConnectionFail => 'Not responding';

  @override
  String get scActiveKey => 'Active key';

  @override
  String get scSetup => 'Set up';

  @override
  String get scReconfigure => 'Reconfigure';

  @override
  String get scStatusAuto => 'The key is picked up automatically';

  @override
  String get scStatusManual => 'Running on your own client_id';

  @override
  String get scGuideTitle => 'How to get a client_id';

  @override
  String get scGuideSubtitle => 'Step-by-step guide — usually not needed';

  @override
  String get scStep1 => 'Open **soundcloud.com** in a desktop browser';

  @override
  String get scStep2 => 'Press **F12** → the **Network** tab';

  @override
  String get scStep3 => 'Press play on any track';

  @override
  String get scStep4 => 'Find the request to **api-v2.soundcloud.com**';

  @override
  String get scStep5 => 'Copy the **client_id** parameter from the URL';

  @override
  String get ymChecking => 'Checking…';

  @override
  String get ymConnected => '✓ Connected';

  @override
  String get ymNotConnected => 'Not connected';

  @override
  String get ymLogout => 'Log out';

  @override
  String get ymPlusActiveA => 'Yandex Plus active';

  @override
  String get ymPlusActiveB => '— tracks play directly from Yandex.';

  @override
  String get ymPlusNoneA => 'No Plus';

  @override
  String get ymPlusNoneB => '— some tracks may be unavailable for playback.';

  @override
  String get ymPlusUnknown => 'Subscription status unknown.';

  @override
  String get ymConnect => 'Connect Yandex Music';

  @override
  String get ymCodePromptA => 'Open';

  @override
  String get ymCodePromptB => 'and enter the code:';

  @override
  String get ymOpenPage => 'Open the page';

  @override
  String get ymCodeCopied => 'Code copied';

  @override
  String get ymGettingCode => 'Getting code…';

  @override
  String get ymWaiting => 'Waiting for confirmation…';

  @override
  String get ymCodeExpired => 'Code expired — press “Connect” again.';

  @override
  String get ymErrAuth => 'Sign in to Yandex again';

  @override
  String get ymErrNeedPlus => 'Yandex Plus required';

  @override
  String get ymErrNetwork => 'Yandex is not responding';

  @override
  String get ymGuideTitle => 'How to connect Yandex Music';

  @override
  String get ymGuideSubtitle => 'Sign in with Yandex ID — four steps';

  @override
  String get ymStep1 => 'Press **Connect Yandex Music**';

  @override
  String get ymStep2 =>
      'The **ya.ru/device** page opens — sign in to your account';

  @override
  String get ymStep3 => 'Enter the code Bloom shows (tap the code to copy it)';

  @override
  String get ymStep4 =>
      'Come back to the app — the connection is picked up on its own';

  @override
  String get ymGuideNote =>
      'Without a Yandex Plus subscription some tracks won\'t play — those can be listened to from other platforms.';

  @override
  String get ytmConfigured => 'Configured';

  @override
  String get ytmNoAuth => 'No authentication needed for now';

  @override
  String get ytmHelp =>
      'Search, pages and link import work without auth. Playback and downloads come straight from YouTube.';

  @override
  String get ytmGuideTitle => 'What already works';

  @override
  String get ytmGuideSubtitle => 'Nothing to connect';

  @override
  String get ytmStep1 =>
      'Search, artist, album and playlist pages — **no sign-in**';

  @override
  String get ytmStep2 =>
      'Link import: paste an album or playlist link in the **Library**';

  @override
  String get ytmStep3 =>
      'Playback and downloads come straight from **YouTube**';

  @override
  String get stOfflineCache => 'Offline track cache';

  @override
  String get stLyrics => 'Lyrics';

  @override
  String get stCustom => 'Customization';

  @override
  String get stUsed => 'Used';

  @override
  String get stManage => 'Clear data';

  @override
  String stCleared(int count) {
    return 'Offline cache cleared: $count';
  }

  @override
  String get stCovers => 'Covers';

  @override
  String get stCoversCleared => 'Cover cache cleared';

  @override
  String get stCoversKeep => 'Keep covers';

  @override
  String get lfmSessionLost => 'The sign-in no longer works — sign in again';

  @override
  String get stLyricsCleared => 'Lyrics cache cleared';

  @override
  String get stLyricsKeep => 'Keep lyrics';

  @override
  String get stLyricsKeepFor => 'Keep lyrics for';

  @override
  String stClearSize(String size) {
    return 'Clear $size';
  }

  @override
  String get stClearSure => 'Really clear?';

  @override
  String stStaleRemoved(int count) {
    return 'Stale removed: $count';
  }

  @override
  String get stKeepNever => 'No limit';

  @override
  String get stKeepRestart => 'Until restart';

  @override
  String get stKeepDay => '24 hours';

  @override
  String get stKeep3Days => '3 days';

  @override
  String get stKeepWeek => '1 week';

  @override
  String get stKeepMonth => '1 month';

  @override
  String get stCustomCleared => 'Library cleared';

  @override
  String get stAllCleared => 'App data cleared';

  @override
  String stKilobytes(String value) {
    return '$value KB';
  }

  @override
  String stMegabytes(String value) {
    return '$value MB';
  }

  @override
  String stGigabytes(String value) {
    return '$value GB';
  }

  @override
  String get ltImportTitle => 'Your own tracks';

  @override
  String get ltImportDesc =>
      'What Bloom does with a file you add with + in All tracks. Tracks already added stay as they are.';

  @override
  String get ltImportInPlace => 'In place';

  @override
  String get ltImportInPlaceTip =>
      'The file stays where it is and takes no extra space. Delete or move it and the track stops playing.';

  @override
  String get ltImportCopy => 'Into Bloom';

  @override
  String get ltImportCopyTip =>
      'Bloom copies the file into itself. The track plays even if the original is gone, but the space is used twice.';

  @override
  String ltAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count tracks',
      one: 'Added $count track',
    );
    return '$_temp0';
  }

  @override
  String get ltNothingAdded => 'Nothing to add';

  @override
  String get ltImportFailed => 'File picker failed';

  @override
  String get ltFileGone => 'File is not available';

  @override
  String get custLibrary => 'Library';

  @override
  String get custPresets => 'Presets';

  @override
  String get custLibraryEmpty => 'Library is empty — add a photo or GIF';

  @override
  String get custAdded => 'Added!';

  @override
  String get custBadUrl => 'Invalid image URL';

  @override
  String custFilesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files added',
      one: '$count file added',
    );
    return '$_temp0';
  }

  @override
  String get custCtxBg => 'Background';

  @override
  String get custCtxCover => 'Cover';

  @override
  String get custCtxSlider => 'Slider';

  @override
  String get custBlur => 'Blur';

  @override
  String get custDim => 'Dim';

  @override
  String get custImageGone => 'Image unavailable';

  @override
  String get custPresetAlsoSave => 'Also save to preset';

  @override
  String get custPresetTheme => 'Theme';

  @override
  String get custPresetTransparency => 'Transparency';

  @override
  String get custPresetFont => 'Font';

  @override
  String get custAttachPhoto => 'Choose from device';

  @override
  String get custBgUpdated => 'Background updated!';

  @override
  String get custCoverUpdated => 'Cover updated!';

  @override
  String get custSliderUpdated => 'Slider photo updated!';

  @override
  String get custBgRemoved => 'Background removed';

  @override
  String get custCoverRemoved => 'Cover reset';

  @override
  String get custSliderRemoved => 'Slider photo removed';

  @override
  String get custApplyTo => 'Apply to';

  @override
  String get custEffects => 'Effects';

  @override
  String get custCoverMode => 'Mode';

  @override
  String get custCoverModeAlways => 'Always';

  @override
  String get custCoverModeFallback => 'If no cover';

  @override
  String get custImport => 'Import';

  @override
  String get custPresetsEmpty => 'Save the current settings as a preset';

  @override
  String get custPresetNameHint => 'Name the preset...';

  @override
  String custPresetSaved(String name) {
    return 'Preset “$name” saved!';
  }

  @override
  String get custPresetNothing => 'Nothing to save';

  @override
  String custPresetsFull(int limit) {
    return 'No room past $limit';
  }

  @override
  String get custPresetUntitled => 'Untitled';

  @override
  String get custPresetApply => 'Apply';

  @override
  String get custPresetExport => 'Export';

  @override
  String custPresetApplied(String name) {
    return 'Preset “$name” applied';
  }

  @override
  String get custPresetExported => 'Preset saved to file';

  @override
  String get custImportBad => 'Invalid file format';

  @override
  String custImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count presets imported',
      one: '$count preset imported',
    );
    return '$_temp0';
  }

  @override
  String get apCoverAsBg => 'Track cover as background';

  @override
  String get apCoverAsBgSub =>
      'Use the current track cover as the app background';

  @override
  String get apTrGroup => 'TRANSPARENCY';

  @override
  String get apTrTitle => 'Transparency';

  @override
  String apTrOn(int percent) {
    return 'On ($percent%)';
  }

  @override
  String get apTrOff => 'Off';

  @override
  String get apTrLevel => 'Transparency level';

  @override
  String get apTrBrightness => 'Glass brightness';

  @override
  String get apTrBlur => 'Glass blur';

  @override
  String get apTrOverlays => 'Overlay transparency';

  @override
  String get apTrOverlaysSub => 'Glass for sheets, menus and dialogs';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String get waveTitle => 'My Wave';

  @override
  String get waveStart => 'Start My Wave';

  @override
  String get wavePickArtist => 'In the style of';

  @override
  String get wavePickTrack => 'By track';

  @override
  String get wavePickNow => 'Now playing';

  @override
  String get waveBack => 'Back to the usual';

  @override
  String get waveShake => 'Shake up My Wave';

  @override
  String get waveLabelTrack => 'Track wave';

  @override
  String get waveLabelQueue => 'Similar to queue';

  @override
  String get waveLabelArtist => 'Artist wave';

  @override
  String get waveFromTrack => 'Wave from this track';

  @override
  String get waveFromArtist => 'Artist wave';

  @override
  String get waveDislikes => 'Dislikes';

  @override
  String get waveDislikesTitle => 'Wave dislikes';

  @override
  String get waveNoDislikes => 'Nothing disliked yet';

  @override
  String get waveDislike => 'Dislike';

  @override
  String get waveUndislike => 'Remove dislike';

  @override
  String get waveToastDisliked => 'Won’t suggest it again';

  @override
  String get waveToastUndisliked => 'Dislike removed';

  @override
  String get waveToastStopped => 'Wave stopped';

  @override
  String get waveToastNotEnough => 'Too little data: play some music';

  @override
  String get waveToastNoSeed => 'No track for a wave';

  @override
  String get waveToastQueueEmpty => 'Queue is empty';

  @override
  String get waveToastNoSeedsInQueue => 'No platform tracks in the queue';

  @override
  String get waveToastArtistNoSeeds => 'No artist tracks for a wave';

  @override
  String get waveToastNoSimilar => 'No similar tracks';

  @override
  String get waveToastYmNoAuth => 'Sign in to Yandex Music';

  @override
  String lfmConnectedAs(String user) {
    return 'Connected as $user';
  }

  @override
  String get lfmNotConnected => 'Not connected';

  @override
  String get lfmLogin => 'Sign in with Last.fm';

  @override
  String get lfmDone => 'Done — I confirmed';

  @override
  String get lfmLogout => 'Log out';

  @override
  String get lfmKeys => 'API keys';

  @override
  String get lfmSaveKeys => 'Save keys';

  @override
  String get lfmScrobble => 'Scrobbling';

  @override
  String get lfmScrobbleSub => 'Count listened tracks on Last.fm';

  @override
  String lfmPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scrobbles wait to be sent',
      one: '$count scrobble waits to be sent',
    );
    return '$_temp0';
  }

  @override
  String get lfmNowPlayingSub => 'Update the “Now Playing” status';

  @override
  String get lfmGuideTitle => 'How to connect Last.fm';

  @override
  String get lfmGuideSubtitle => 'Your own app key and a browser sign-in';

  @override
  String get lfmStep1 =>
      'Open **last.fm/api/account/create** and register an app — any name will do.';

  @override
  String get lfmStep2 =>
      'Copy **API Key** and **Shared Secret** from there and paste them into the fields below.';

  @override
  String get lfmStep3 =>
      'Tap **“Sign in with Last.fm”** — the browser opens, and the password is only entered there.';

  @override
  String get lfmStep4 =>
      'Allow access and come back to Bloom: the app checks the sign-in by itself.';

  @override
  String get lfmGuideNote =>
      'The key has to be your own — Bloom has no shared Last.fm key. Your password is never entered into the app.';

  @override
  String get lfmGettingToken => 'Getting token…';

  @override
  String get lfmConfirmAccess => 'Confirm access on Last.fm, then press “Done”';

  @override
  String get lfmChecking => 'Checking…';

  @override
  String get lfmNotConfirmed => 'Not confirmed — try again';

  @override
  String get lfmLoginFirst => 'Press “Sign in with Last.fm” first';

  @override
  String get lfmNeedKeys => 'Save the API Key and Secret first';

  @override
  String get lfmNetworkError => 'Network error';

  @override
  String lfmError(String msg) {
    return 'Error: $msg';
  }

  @override
  String lfmToastConnected(String name) {
    return 'Last.fm: connected as $name';
  }

  @override
  String get lfmToastDisconnected => 'Last.fm: disconnected';

  @override
  String get lfmToastKeysSaved => 'Last.fm: keys saved';

  @override
  String get wrMonth => 'Month in review';

  @override
  String get wrYear => 'Year in review';

  @override
  String get wrNext => 'Next';

  @override
  String get wrClose => 'Close';

  @override
  String get wrWatch => 'Watch';

  @override
  String get wrNew => 'New';

  @override
  String get wrIntroMonth => 'Your month in Bloom';

  @override
  String get wrIntroYear => 'Your year in Bloom';

  @override
  String get wrIntroSub => 'Let’s see how it went';

  @override
  String get wrTimeKicker => 'You listened for';

  @override
  String wrTimeSub(int count) {
    return 'Plays in this period: $count';
  }

  @override
  String get wrTimeLessThanMin => 'Less than a minute';

  @override
  String get wrCountsTitle => 'Here’s the whole picture';

  @override
  String wrCountsNewTracks(int count) {
    return 'Heard for the first time: $count';
  }

  @override
  String wrArtistsTotalN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artists in total',
      one: '$count artist in total',
    );
    return '$_temp0';
  }

  @override
  String get wrSourcesKicker => 'Where it came from';

  @override
  String get wrDiscoverKicker => 'New names';

  @override
  String wrDiscoverTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You discovered $count artists',
      one: 'You discovered $count artist',
    );
    return '$_temp0';
  }

  @override
  String get wrHabitsKicker => 'Your habits';

  @override
  String get wrHabitsNight => 'You’re a night listener';

  @override
  String get wrHabitsDay => 'You’re a daytime listener';

  @override
  String get wrHabitsPeak => 'Favorite hour';

  @override
  String get wrHabitsRecord => 'Day record';

  @override
  String get wrHabitsStreak => 'Days in a row';

  @override
  String get wrHabitsActive => 'Days with music';

  @override
  String wrHabitsRecordValue(Object tracks, Object date) {
    return '$tracks · $date';
  }

  @override
  String get wrShareKicker => 'Keep it';

  @override
  String get wrShareSave => 'Share';

  @override
  String get wrShareFail => 'Couldn’t share the card';

  @override
  String get wrCardTime => 'Time with music';

  @override
  String get wrCardTopTracks => 'Top tracks';

  @override
  String get wrCardTopArtists => 'Top artists';

  @override
  String get wrJokeTiny => 'Kind of empty. Did you even press play?';

  @override
  String get wrJokeSmall => 'Modest. But we counted every single track.';

  @override
  String get wrJokeOneTrack =>
      'One track, one artist — respect the consistency.';

  @override
  String wrPlaysWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'plays',
      one: 'play',
    );
    return '$_temp0';
  }

  @override
  String wrTracksN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '$count track',
    );
    return '$_temp0';
  }

  @override
  String wrTracksWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$_temp0';
  }

  @override
  String wrArtistsWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'artists',
      one: 'artist',
    );
    return '$_temp0';
  }

  @override
  String wrDaysN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String wrHoursN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '$count hour',
    );
    return '$_temp0';
  }

  @override
  String wrHoursWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hours',
      one: 'hour',
    );
    return '$_temp0';
  }

  @override
  String wrMinutesN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '$count minute',
    );
    return '$_temp0';
  }

  @override
  String wrMinutesWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'minutes',
      one: 'minute',
    );
    return '$_temp0';
  }

  @override
  String wrTimesN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '$count time',
    );
    return '$_temp0';
  }

  @override
  String wrTimesWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'times',
      one: 'time',
    );
    return '$_temp0';
  }

  @override
  String wrHourRange(Object from, Object to) {
    return '$from — $to';
  }

  @override
  String get sysStartup => 'Startup';

  @override
  String get audRestoreTitle => 'Restore the queue';

  @override
  String get audRestoreSub =>
      'Bring the track, queue and position back on launch — paused';

  @override
  String get audQueue => 'Queue';

  @override
  String get audAutoSimilarTitle => 'Autoplay similar';

  @override
  String get audAutoSimilarSub =>
      'Automatically load similar tracks when there is no next one';

  @override
  String get audAutoplayTitle => 'Autoplay';

  @override
  String get audAutoplaySub =>
      'Restore the last session on launch and keep playing right away';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutChecking => 'Checking for updates…';

  @override
  String get aboutRecheck => 'Check again';

  @override
  String aboutInstalled(String v) {
    return 'Version $v installed';
  }

  @override
  String get aboutUptodate => 'You have the latest version';

  @override
  String aboutAvailable(String v) {
    return 'Version $v is available';
  }

  @override
  String get aboutError => 'Couldn’t check for updates';

  @override
  String get aboutOpenRelease => 'Open the release page';

  @override
  String get updInThis => 'In this version';

  @override
  String get updWhatsNew => 'What’s new';

  @override
  String get updHistory => 'Update history';

  @override
  String get updHistorySub => 'Notes for previous versions';

  @override
  String get updHistoryEmpty => 'There are no release notes yet';

  @override
  String get updNotesEmpty => 'No notes for this version';

  @override
  String get updNotesError => 'Couldn’t load the release notes';

  @override
  String get sysImportExport => 'Import/Export';

  @override
  String get sysExportTitle => 'Export all';

  @override
  String get sysExportSub => 'Save every playlist to a .bloomplaylist file';

  @override
  String get sysExportFilename => 'bloom-playlists.bloomplaylist';

  @override
  String get sysExported => 'File saved';

  @override
  String get sysImportTitle => 'Import';

  @override
  String get sysImportSub => 'Load playlists from a .bloomplaylist file';

  @override
  String get sysImportInvalid => 'Error: invalid file';

  @override
  String get sysImportNoPlaylists => 'No playlists found';

  @override
  String get sysImportOld => 'Format not supported';

  @override
  String get sysImportNewer => 'Newer file: update Bloom';

  @override
  String sysImportedFull(int pl, int tr) {
    return 'Imported: $pl pl., $tr tr.';
  }

  @override
  String sysImportedPlaylists(int pl) {
    return 'Playlists imported: $pl';
  }

  @override
  String get sysLogs => 'Logs';

  @override
  String get sysLogTitle => 'Activity log';

  @override
  String get sysLogEmptySub => 'Nothing yet';

  @override
  String sysLogEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '$count entry',
    );
    return '$_temp0';
  }

  @override
  String get logsCopy => 'Copy';

  @override
  String get logsSave => 'Save';

  @override
  String get logsClear => 'Clear';

  @override
  String get logsCopied => 'Copied';

  @override
  String get logsSaved => 'Logs saved';

  @override
  String get logsCleared => 'Logs cleared';

  @override
  String get logsEmpty => 'The log is empty';

  @override
  String get sysDangerZone => 'Danger zone';

  @override
  String get sysResetTitle => 'Reset settings';

  @override
  String get sysResetSub => 'Return the look and the options to their defaults';

  @override
  String get sysResetBody =>
      'The look, the player, gestures, transparency and customization presets go back to their defaults. Your library, history, profile and platform logins stay.';

  @override
  String get sysResetBtn => 'Reset';

  @override
  String get sysResetDone => 'Settings reset';

  @override
  String get sysHardResetTitle => 'Reset everything';

  @override
  String get sysHardResetSub =>
      'Delete tracks, playlists, history and settings';

  @override
  String get sysHardResetBody =>
      'The library, playlists, history, profile, downloads and every setting will be erased for good. There will be nothing to bring them back with.';

  @override
  String get sysHardResetBtn => 'Reset everything';

  @override
  String get sysHardResetDone => 'Everything is erased';

  @override
  String get playerSkipDrm => 'Track is DRM-protected — skipping';

  @override
  String get playerSkipUnavailable => 'Track unavailable — skipping';

  @override
  String get playerNoPlayable => 'No tracks to play';

  @override
  String get errDrm => 'Track is DRM-protected';

  @override
  String get errNoStream => 'No stream data';

  @override
  String get errTrackNotFound => 'Track not found';

  @override
  String get errScUnavailable => 'SoundCloud is not responding';

  @override
  String get errScForbidden => 'SoundCloud: access denied';

  @override
  String get errScClientId => 'SoundCloud: client_id expired';

  @override
  String get errYtmNoAudio => 'YouTube gave no audio';

  @override
  String get errYtmNetwork => 'YouTube is not responding';

  @override
  String get apFontCat => 'FONT';

  @override
  String get apFontTitle => 'Interface font';

  @override
  String get apFontDesc => 'Choose a font for the whole app';

  @override
  String get apFontAdd => 'Upload your own font';

  @override
  String get apFontRemove => 'Remove font';

  @override
  String apFontAdded(int n) {
    return 'Fonts added: $n';
  }

  @override
  String get apFontBadFormat => 'Only .ttf and .otf';

  @override
  String apFontTooBig(int mb) {
    return 'Font is over $mb MB';
  }

  @override
  String get apFontReadErr => 'Couldn’t read the font';

  @override
  String get setPc => 'Computer';

  @override
  String get pcNotPaired => 'Not connected';

  @override
  String get pcPlayOn => 'Play on';

  @override
  String get pcThisPhone => 'This phone';

  @override
  String pcPairedTo(String name) {
    return 'Connected to “$name”';
  }

  @override
  String pcSyncedAt(String when) {
    return 'Synced $when';
  }

  @override
  String get pcSyncing => 'Syncing…';

  @override
  String get pcOffline => 'The computer isn\'t on the network';

  @override
  String get pcRepair =>
      'The computer no longer knows this phone — connect again';

  @override
  String get pcFailed => 'Couldn\'t sync';

  @override
  String get pcStep1 =>
      'Open **Bloom** on the computer: **Settings → Integrations → Phone** and turn the mode on.';

  @override
  String get pcStep2 =>
      'Press **Connect a phone** — a QR code and a six-digit code show up.';

  @override
  String get pcStep3 =>
      'Here press **Scan the QR code** and point the camera at it — or **Type the code**.';

  @override
  String get pcGuideNote =>
      'The phone and the computer must be on the same home network. Playlists, likes, follows, dislikes, history and the profile sync; settings stay each device\'s own.';

  @override
  String get pcScan => 'Scan the QR code';

  @override
  String get pcEnterCode => 'Type the code';

  @override
  String get pcSyncNow => 'Sync now';

  @override
  String get pcReconnect => 'Connect again';

  @override
  String get pcUnpair => 'Disconnect';

  @override
  String get pcUnpairTitle => 'Disconnect the computer?';

  @override
  String pcUnpairBody(String name) {
    return 'Syncing with “$name” stops. To connect again you\'ll need the computer: Connect a phone on its screen.';
  }

  @override
  String get pcUnpaired => 'Forgotten. Disconnect it there too';

  @override
  String get pcScanHint =>
      'Point the camera at the QR code on the computer\'s screen';

  @override
  String get pcNoCamera => 'No access to the camera';

  @override
  String get pcCodeSearching => 'Looking for the computer…';

  @override
  String get pcCodeNone =>
      'No computer found. Open “Connect a phone” on it — the phone must be on the same network.';

  @override
  String get pcCodeRetry => 'Search again';

  @override
  String get pcCodeHint => 'The code from the computer\'s screen';

  @override
  String get pcConnect => 'Connect';

  @override
  String pcPaired(String name) {
    return 'Connected to “$name”';
  }

  @override
  String get pcSynced => 'Synced';

  @override
  String get pcErrNotBloom => 'That\'s not a Bloom code';

  @override
  String get pcErrUnreachable => 'No answer. Same network?';

  @override
  String get pcErrWrong => 'Wrong code';

  @override
  String get pcErrClosed => 'Closed on the computer';

  @override
  String get pcErrTooMany => 'Too many tries: get a new code';

  @override
  String get pcErrFailed => 'Couldn\'t connect';

  @override
  String get taPlayNextHint => 'Plays after the current one';

  @override
  String get waveFromTrackHint => 'A mix of similar tracks';

  @override
  String get waveFromArtistHint => 'A mix based on this artist';

  @override
  String get waveDislikeHint => 'Won\'t show up in mixes';

  @override
  String get waveUndislikeHint => 'Back in the mixes';

  @override
  String get tiHint => 'Album, year, length';

  @override
  String get tlOfflineHint => 'A copy inside the app';

  @override
  String get tlFilesHint => 'To the phone\'s files';

  @override
  String get tlRefreshHint => 'What\'s new in the sources';

  @override
  String get commonPinHint => 'First in the library';

  @override
  String get tlMergeHint => 'Into a new playlist';

  @override
  String get tlConvertHint => 'A copy on another platform';

  @override
  String get tlFindDupsHint => 'Repeats in this list';

  @override
  String get tlExportHint => 'To a transfer file';

  @override
  String get artistImportHint => 'Into your library';

  @override
  String get commonFollowHint => 'The artist joins your library';
}
