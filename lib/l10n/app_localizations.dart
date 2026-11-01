import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// desktop: common.undo — default toast action label
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get commonUpload;

  /// phone only: collapses the setup block on a platform page
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get commonHide;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// phone only: separator between the guide card and manual input
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get commonOr;

  /// desktop: settings.interface.titlebar.item.pin
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get commonPin;

  /// desktop: lib.sidebar.unpin
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get commonUnpin;

  /// desktop: player.aria.play
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get commonPlay;

  /// wide button on a list page while that very list is playing
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get commonPause;

  /// desktop: player.aria.shuffle
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get commonShuffle;

  /// desktop: search.follow
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get commonFollow;

  /// desktop: search.unfollow
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get commonUnfollow;

  /// desktop: search.loadMore
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get commonLoadMore;

  /// desktop: search.kind.track
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get commonTrack;

  /// No description provided for @commonAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get commonAlbum;

  /// No description provided for @commonPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get commonPlaylist;

  /// No description provided for @commonArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get commonArtist;

  /// desktop: search.kind.profile
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get commonProfile;

  /// desktop: search.tab.tracks
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get commonTracks;

  /// No description provided for @commonPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get commonPlaylists;

  /// desktop: search.tab.albums
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get commonAlbums;

  /// desktop: search.tab.artists
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get commonArtists;

  /// desktop: player.queueTitle.all
  ///
  /// In en, this message translates to:
  /// **'All tracks'**
  String get commonAllTracks;

  /// desktop: player.queueTitle.fav
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get commonFavorites;

  /// desktop: settings.home.item.history
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get commonHistory;

  /// desktop: player.add.newPlaylist
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get commonNewPlaylist;

  /// desktop: player.add.createPlaylist
  ///
  /// In en, this message translates to:
  /// **'Create playlist'**
  String get commonCreatePlaylist;

  /// desktop: player.add.toLib
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get commonAddToLibrary;

  /// No description provided for @commonAlreadyInLibrary.
  ///
  /// In en, this message translates to:
  /// **'Already in your library'**
  String get commonAlreadyInLibrary;

  /// desktop: common.unknownArtist — a local file whose tags carry no artist
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknownArtist;

  /// desktop: lib.plmenu.offlineBadge
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get commonOfflineBadge;

  /// label before the date a track joined the library, in a sheet header
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get commonAddedOn;

  /// label before the date a playlist was created, in a sheet header
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get commonCreatedOn;

  /// desktop: fmtTotalDur — total time of a list, an hour or longer
  ///
  /// In en, this message translates to:
  /// **'{h}h {m}m'**
  String commonDurHm(int h, int m);

  /// desktop: fmtTotalDur — total time of a list, under an hour
  ///
  /// In en, this message translates to:
  /// **'{m} min'**
  String commonDurMin(int m);

  /// Replaces the hand-rolled tracksCount() from shared/util/format.dart
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} track} other{{count} tracks}}'**
  String tracksCount(int count);

  /// desktop: stats.playsCount
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} play} other{{count} plays}}'**
  String playsCount(int count);

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @sourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get sourceLocal;

  /// desktop: settings.nav.yandex
  ///
  /// In en, this message translates to:
  /// **'Yandex Music'**
  String get sourceYandex;

  /// No description provided for @homeCharts.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get homeCharts;

  /// No description provided for @homeNewReleases.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get homeNewReleases;

  /// desktop: chart.up
  ///
  /// In en, this message translates to:
  /// **'Up {n}'**
  String chartUp(int n);

  /// desktop: chart.down
  ///
  /// In en, this message translates to:
  /// **'Down {n}'**
  String chartDown(int n);

  /// No description provided for @chartSame.
  ///
  /// In en, this message translates to:
  /// **'No change'**
  String get chartSame;

  /// No description provided for @chartNew.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get chartNew;

  /// No description provided for @chartNewShort.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get chartNewShort;

  /// No description provided for @relAlbum.
  ///
  /// In en, this message translates to:
  /// **'album'**
  String get relAlbum;

  /// No description provided for @relSingle.
  ///
  /// In en, this message translates to:
  /// **'single'**
  String get relSingle;

  /// No description provided for @relCompilation.
  ///
  /// In en, this message translates to:
  /// **'compilation'**
  String get relCompilation;

  /// No description provided for @relPodcast.
  ///
  /// In en, this message translates to:
  /// **'podcast'**
  String get relPodcast;

  /// desktop: home.rel.ep
  ///
  /// In en, this message translates to:
  /// **'EP'**
  String get relEp;

  /// No description provided for @homeForYou.
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get homeForYou;

  /// No description provided for @homeForYouAll.
  ///
  /// In en, this message translates to:
  /// **'All picks'**
  String get homeForYouAll;

  /// No description provided for @homeSimilarTo.
  ///
  /// In en, this message translates to:
  /// **'Similar to'**
  String get homeSimilarTo;

  /// No description provided for @homeSimilarArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get homeSimilarArtist;

  /// desktop: settings.view.mpEl.queue
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get playerQueue;

  /// desktop: player.queue.section.played — section of the extended queue view
  ///
  /// In en, this message translates to:
  /// **'Played'**
  String get queueSecPlayed;

  /// desktop: player.queue.section.now
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get queueSecNow;

  /// desktop: player.queue.section.next
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get queueSecNext;

  /// Плашка под слайдером плеера: какой трек заиграет следующим
  ///
  /// In en, this message translates to:
  /// **'Up next: {title}'**
  String playerNextUp(String title);

  /// Подпись источника очереди, набранной из выдачи поиска
  ///
  /// In en, this message translates to:
  /// **'Search: {query}'**
  String playerSourceSearch(String query);

  /// desktop: player.toast.copied
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get playerCopied;

  /// desktop: player.toast.copyError
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get playerCopyError;

  /// desktop: player.aria.speed (Playback speed)
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get playerSpeed;

  /// desktop: player.speed.custom
  ///
  /// In en, this message translates to:
  /// **'Custom speed'**
  String get playerSpeedCustom;

  /// desktop: player.speed.reset
  ///
  /// In en, this message translates to:
  /// **'Reset to 1×'**
  String get playerSpeedReset;

  /// desktop: player.speed.nightcore
  ///
  /// In en, this message translates to:
  /// **'Nightcore'**
  String get playerSpeedNightcore;

  /// desktop: player.speed.nightcoreSub
  ///
  /// In en, this message translates to:
  /// **'Pitch follows the speed'**
  String get playerSpeedNightcoreSub;

  /// Мобильная фича, десктопного оригинала нет
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get playerSleep;

  /// Подпись под числом на карточке-пресете таймера сна
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get playerSleepMin;

  /// Время таймера сна в пилюле и на краях полосы
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String playerSleepMinutes(int count);

  /// Остаток таймера сна в шапке шторки
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String playerSleepLeft(String time);

  /// No description provided for @playerSleepEndOfTrack.
  ///
  /// In en, this message translates to:
  /// **'Until end of track'**
  String get playerSleepEndOfTrack;

  /// No description provided for @playerSleepCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom time'**
  String get playerSleepCustom;

  /// No description provided for @playerSleepExtend.
  ///
  /// In en, this message translates to:
  /// **'+5 minutes'**
  String get playerSleepExtend;

  /// No description provided for @playerSleepCancel.
  ///
  /// In en, this message translates to:
  /// **'Turn off timer'**
  String get playerSleepCancel;

  /// No description provided for @playerSleepFade.
  ///
  /// In en, this message translates to:
  /// **'Fade out'**
  String get playerSleepFade;

  /// No description provided for @playerSleepFadeSub.
  ///
  /// In en, this message translates to:
  /// **'Volume drops to zero over the last 20 seconds'**
  String get playerSleepFadeSub;

  /// No description provided for @notifChannelName.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get notifChannelName;

  /// No description provided for @notifChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Music controls in the notification shade and on the lock screen'**
  String get notifChannelDescription;

  /// No description provided for @artistSourceNotConnected.
  ///
  /// In en, this message translates to:
  /// **'This artist’s source isn’t connected'**
  String get artistSourceNotConnected;

  /// No description provided for @artistNotFound.
  ///
  /// In en, this message translates to:
  /// **'Artist not found'**
  String get artistNotFound;

  /// desktop: search.popular
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get artistPopular;

  /// desktop: search.similarArtists
  ///
  /// In en, this message translates to:
  /// **'Fans might also like'**
  String get artistSimilar;

  /// No description provided for @artistNoTracks.
  ///
  /// In en, this message translates to:
  /// **'This artist has no available tracks'**
  String get artistNoTracks;

  /// No description provided for @artistAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get artistAbout;

  /// No description provided for @artistAboutProfile.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get artistAboutProfile;

  /// No description provided for @artistLikes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get artistLikes;

  /// No description provided for @artistShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get artistShowAll;

  /// No description provided for @artistImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get artistImport;

  /// No description provided for @artistImportLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading all of the artist\'s tracks…'**
  String get artistImportLoading;

  /// No description provided for @artistLikesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading all of the likes…'**
  String get artistLikesLoading;

  /// No description provided for @likesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} like} other{{count} likes}}'**
  String likesCount(int count);

  /// No description provided for @artistNotFoundOnSource.
  ///
  /// In en, this message translates to:
  /// **'Not found on the source'**
  String get artistNotFoundOnSource;

  /// No description provided for @followedToast.
  ///
  /// In en, this message translates to:
  /// **'Following {name}'**
  String followedToast(String name);

  /// No description provided for @unfollowedToast.
  ///
  /// In en, this message translates to:
  /// **'Unfollowed'**
  String get unfollowedToast;

  /// tracks is an already-formatted tracksCount string
  ///
  /// In en, this message translates to:
  /// **'Added: {title} — {tracks}'**
  String addedToast(String title, String tracks);

  /// No description provided for @setSourceNotConnected.
  ///
  /// In en, this message translates to:
  /// **'This list’s source isn’t connected'**
  String get setSourceNotConnected;

  /// No description provided for @setAlbumNotFound.
  ///
  /// In en, this message translates to:
  /// **'Album not found'**
  String get setAlbumNotFound;

  /// No description provided for @setPlaylistNotFound.
  ///
  /// In en, this message translates to:
  /// **'Playlist not found'**
  String get setPlaylistNotFound;

  /// No description provided for @setNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks available'**
  String get setNoTracks;

  /// No description provided for @libTabAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libTabAll;

  /// No description provided for @libTabArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get libTabArtists;

  /// No description provided for @libSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get libSystem;

  /// No description provided for @libAllTracksSub.
  ///
  /// In en, this message translates to:
  /// **'The whole library'**
  String get libAllTracksSub;

  /// No description provided for @libLikedSub.
  ///
  /// In en, this message translates to:
  /// **'Liked tracks'**
  String get libLikedSub;

  /// No description provided for @libNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks'**
  String get libNoTracks;

  /// No description provided for @libAutoRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Playlist auto-refresh'**
  String get libAutoRefreshTooltip;

  /// No description provided for @libSortManual.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get libSortManual;

  /// No description provided for @libSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'By name A–Z'**
  String get libSortNameAsc;

  /// No description provided for @libSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'By name Z–A'**
  String get libSortNameDesc;

  /// No description provided for @tlSortManual.
  ///
  /// In en, this message translates to:
  /// **'In order'**
  String get tlSortManual;

  /// No description provided for @tlSortName.
  ///
  /// In en, this message translates to:
  /// **'By title'**
  String get tlSortName;

  /// No description provided for @tlSortArtist.
  ///
  /// In en, this message translates to:
  /// **'By artist'**
  String get tlSortArtist;

  /// No description provided for @tlSortAlbum.
  ///
  /// In en, this message translates to:
  /// **'By album'**
  String get tlSortAlbum;

  /// No description provided for @tlSortDuration.
  ///
  /// In en, this message translates to:
  /// **'By length'**
  String get tlSortDuration;

  /// No description provided for @tlSortDate.
  ///
  /// In en, this message translates to:
  /// **'By date added'**
  String get tlSortDate;

  /// No description provided for @tlSortPlays.
  ///
  /// In en, this message translates to:
  /// **'By plays'**
  String get tlSortPlays;

  /// No description provided for @tlSortDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded only'**
  String get tlSortDownloaded;

  /// No description provided for @tlSortNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded only'**
  String get tlSortNotDownloaded;

  /// No description provided for @tlNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get tlNothingFound;

  /// No description provided for @tlNothingDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Nothing downloaded here'**
  String get tlNothingDownloaded;

  /// No description provided for @tlNothingNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Everything here is downloaded'**
  String get tlNothingNotDownloaded;

  /// No description provided for @tlEmptyFav.
  ///
  /// In en, this message translates to:
  /// **'Nothing liked yet'**
  String get tlEmptyFav;

  /// desktop: historyLabel() group header in the History view
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get histToday;

  /// No description provided for @histYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get histYesterday;

  /// No description provided for @histDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day ago} other{{count} days ago}}'**
  String histDaysAgo(int count);

  /// No description provided for @histWeekAgo.
  ///
  /// In en, this message translates to:
  /// **'A week ago'**
  String get histWeekAgo;

  /// No description provided for @tlEmptyAll.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get tlEmptyAll;

  /// No description provided for @tlEmptyPlaylist.
  ///
  /// In en, this message translates to:
  /// **'This playlist is empty'**
  String get tlEmptyPlaylist;

  /// No description provided for @tlSearchHint.
  ///
  /// In en, this message translates to:
  /// **'In this list'**
  String get tlSearchHint;

  /// desktop: lib.jumpToNow — floating pill that scrolls the tracklist back to the playing track
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get tlJumpToNow;

  /// No description provided for @tlStopSaving.
  ///
  /// In en, this message translates to:
  /// **'Stop saving'**
  String get tlStopSaving;

  /// desktop: lib.plmenu.removeOfflinePlaylist
  ///
  /// In en, this message translates to:
  /// **'Remove from offline'**
  String get tlRemoveOffline;

  /// No description provided for @tlListenOffline.
  ///
  /// In en, this message translates to:
  /// **'Listen offline ({count})'**
  String tlListenOffline(int count);

  /// No description provided for @tlDownloadFiles.
  ///
  /// In en, this message translates to:
  /// **'Download as files ({count})'**
  String tlDownloadFiles(int count);

  /// No description provided for @tlRefreshTracks.
  ///
  /// In en, this message translates to:
  /// **'Refresh tracks'**
  String get tlRefreshTracks;

  /// desktop: lib.plmenu.toQueue — append the whole list to the queue
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get tlToQueue;

  /// desktop: lib.plmenu.playNext
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get tlPlayNext;

  /// desktop: toast.addedToQueue
  ///
  /// In en, this message translates to:
  /// **'Added to queue: {count}'**
  String tlQueuedTracks(int count);

  /// desktop: toast.queuedNext
  ///
  /// In en, this message translates to:
  /// **'Playing next: {count}'**
  String tlQueuedNext(int count);

  /// desktop: lib.plmenu.exportPlaylist
  ///
  /// In en, this message translates to:
  /// **'Export playlist'**
  String get tlExportPlaylist;

  /// No description provided for @tlDeletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get tlDeletePlaylist;

  /// No description provided for @tlPlaylistDeleted.
  ///
  /// In en, this message translates to:
  /// **'Playlist “{name}” deleted'**
  String tlPlaylistDeleted(String name);

  /// desktop: lib.plmenu.deletePlaylistWithTracks
  ///
  /// In en, this message translates to:
  /// **'Delete playlist and tracks'**
  String get tlDeletePlaylistWithTracks;

  /// No description provided for @tlPlaylistAndTracksDeleted.
  ///
  /// In en, this message translates to:
  /// **'Playlist “{name}” and its tracks deleted'**
  String tlPlaylistAndTracksDeleted(String name);

  /// No description provided for @leAddedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Liked: {tracks}'**
  String leAddedToFavorites(String tracks);

  /// No description provided for @leRemovedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Unliked: {tracks}'**
  String leRemovedFromFavorites(String tracks);

  /// No description provided for @leDeleteArm.
  ///
  /// In en, this message translates to:
  /// **'Tap again — {tracks} will be gone everywhere'**
  String leDeleteArm(String tracks);

  /// No description provided for @leDiscardArm.
  ///
  /// In en, this message translates to:
  /// **'Tap again to discard your changes'**
  String get leDiscardArm;

  /// No description provided for @cpImported.
  ///
  /// In en, this message translates to:
  /// **'Imported: {title} — {count}'**
  String cpImported(String title, int count);

  /// No description provided for @cpAllAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'All of it is already in your library'**
  String get cpAllAlreadyIn;

  /// No description provided for @cpAdded.
  ///
  /// In en, this message translates to:
  /// **'Added: {count}'**
  String cpAdded(int count);

  /// No description provided for @cpSourceNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t respond'**
  String get cpSourceNoAnswer;

  /// No description provided for @cpNameHint.
  ///
  /// In en, this message translates to:
  /// **'My playlist'**
  String get cpNameHint;

  /// desktop: lib.add.import
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get cpImport;

  /// No description provided for @cpLinkHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a link…'**
  String get cpLinkHint;

  /// desktop: lib.import.fromFile
  ///
  /// In en, this message translates to:
  /// **'From file'**
  String get cpFromFile;

  /// No description provided for @cpDestination.
  ///
  /// In en, this message translates to:
  /// **'To: {target}'**
  String cpDestination(String target);

  /// No description provided for @paEveryMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String paEveryMinutes(int count);

  /// No description provided for @paEveryHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String paEveryHours(int count);

  /// No description provided for @paJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get paJustNow;

  /// No description provided for @paMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String paMinutesAgo(int count);

  /// No description provided for @paHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String paHoursAgo(int count);

  /// No description provided for @paDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String paDaysAgo(int count);

  /// No description provided for @paTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-refresh'**
  String get paTitle;

  /// No description provided for @paAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Refresh automatically'**
  String get paAutoTitle;

  /// No description provided for @paAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pull new tracks from the sources on a schedule'**
  String get paAutoSubtitle;

  /// No description provided for @paOnStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Check on launch'**
  String get paOnStartTitle;

  /// No description provided for @paOnStartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One pass a few seconds after start'**
  String get paOnStartSubtitle;

  /// No description provided for @paPlaylistsWithSources.
  ///
  /// In en, this message translates to:
  /// **'Playlists with sources'**
  String get paPlaylistsWithSources;

  /// No description provided for @paSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get paSelectAll;

  /// No description provided for @paDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get paDeselectAll;

  /// No description provided for @paNothingToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Nothing to refresh: no playlist has sources yet. Link one while editing a playlist — or import a playlist from a link and it remembers its own.'**
  String get paNothingToRefresh;

  /// No description provided for @paRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing…'**
  String get paRefreshing;

  /// No description provided for @paNeverRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Never refreshed'**
  String get paNeverRefreshed;

  /// No description provided for @paLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last pass: {ago}'**
  String paLastRun(String ago);

  /// No description provided for @paSoon.
  ///
  /// In en, this message translates to:
  /// **'any moment'**
  String get paSoon;

  /// No description provided for @paNextIn.
  ///
  /// In en, this message translates to:
  /// **'in {time}'**
  String paNextIn(String time);

  /// No description provided for @paSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {selected} of {total}'**
  String paSelected(int selected, int total);

  /// No description provided for @paPeriod.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get paPeriod;

  /// No description provided for @paRunUpdating.
  ///
  /// In en, this message translates to:
  /// **'refreshing…'**
  String get paRunUpdating;

  /// No description provided for @paRunError.
  ///
  /// In en, this message translates to:
  /// **'error'**
  String get paRunError;

  /// No description provided for @paRunNoChanges.
  ///
  /// In en, this message translates to:
  /// **'no changes'**
  String get paRunNoChanges;

  /// No description provided for @paRefreshNow.
  ///
  /// In en, this message translates to:
  /// **'Refresh now'**
  String get paRefreshNow;

  /// No description provided for @paBusy.
  ///
  /// In en, this message translates to:
  /// **'Refreshing {count}…'**
  String paBusy(int count);

  /// No description provided for @paProgress.
  ///
  /// In en, this message translates to:
  /// **'Refreshing: {done}/{total}'**
  String paProgress(int done, int total);

  /// No description provided for @paNewTracks.
  ///
  /// In en, this message translates to:
  /// **'New tracks: {added} (playlists: {playlists})'**
  String paNewTracks(int added, int playlists);

  /// No description provided for @paFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t refresh playlists: {count}'**
  String paFailed(int count);

  /// No description provided for @paNoNewTracks.
  ///
  /// In en, this message translates to:
  /// **'No new tracks'**
  String get paNoNewTracks;

  /// No description provided for @rpBusy.
  ///
  /// In en, this message translates to:
  /// **'Refreshing “{name}”…'**
  String rpBusy(String name);

  /// No description provided for @rpNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t respond'**
  String get rpNoAnswer;

  /// No description provided for @rpNewTracks.
  ///
  /// In en, this message translates to:
  /// **'New tracks: {count}'**
  String rpNewTracks(int count);

  /// No description provided for @psTitle.
  ///
  /// In en, this message translates to:
  /// **'Update sources'**
  String get psTitle;

  /// No description provided for @psHint.
  ///
  /// In en, this message translates to:
  /// **'Link playlists, albums or likes from any platform — “Refresh tracks” will add new tracks from them to the top of this playlist.'**
  String get psHint;

  /// No description provided for @psAddHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a playlist, album or profile link…'**
  String get psAddHint;

  /// No description provided for @psAdd.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get psAdd;

  /// No description provided for @psRemove.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get psRemove;

  /// No description provided for @psDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This source is already linked'**
  String get psDuplicate;

  /// No description provided for @iuUnrecognized.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t make sense of that link'**
  String get iuUnrecognized;

  /// No description provided for @iuLikesTitle.
  ///
  /// In en, this message translates to:
  /// **'Likes · {name}'**
  String iuLikesTitle(String name);

  /// No description provided for @iuOnlySupported.
  ///
  /// In en, this message translates to:
  /// **'Only a playlist, an album or likes can be pasted'**
  String get iuOnlySupported;

  /// No description provided for @iuNoTracks.
  ///
  /// In en, this message translates to:
  /// **'That link has no tracks'**
  String get iuNoTracks;

  /// No description provided for @iuPlaylistGone.
  ///
  /// In en, this message translates to:
  /// **'That playlist no longer exists'**
  String get iuPlaylistGone;

  /// No description provided for @ofRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from offline'**
  String get ofRemoved;

  /// No description provided for @ofSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving for offline…'**
  String get ofSaving;

  /// No description provided for @ofAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available offline: {name}'**
  String ofAvailable(String name);

  /// No description provided for @ofNothingToSave.
  ///
  /// In en, this message translates to:
  /// **'Nothing here to save offline'**
  String get ofNothingToSave;

  /// No description provided for @ofDownloadingTrack.
  ///
  /// In en, this message translates to:
  /// **'Downloading track…'**
  String get ofDownloadingTrack;

  /// No description provided for @ofSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: {path}'**
  String ofSaved(String path);

  /// No description provided for @ofDownloadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Downloading files…'**
  String get ofDownloadingFiles;

  /// No description provided for @ofNothingToDownload.
  ///
  /// In en, this message translates to:
  /// **'Nothing here to download'**
  String get ofNothingToDownload;

  /// No description provided for @ofNoCopies.
  ///
  /// In en, this message translates to:
  /// **'There were no offline copies'**
  String get ofNoCopies;

  /// No description provided for @ofRemovedCount.
  ///
  /// In en, this message translates to:
  /// **'Removed from offline: {count}'**
  String ofRemovedCount(int count);

  /// No description provided for @ofSavingProgress.
  ///
  /// In en, this message translates to:
  /// **'Saving: {done}/{total}'**
  String ofSavingProgress(int done, int total);

  /// No description provided for @ofAbort.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get ofAbort;

  /// No description provided for @ofNoStorage.
  ///
  /// In en, this message translates to:
  /// **'No access to storage'**
  String get ofNoStorage;

  /// No description provided for @ofCantSaveTrack.
  ///
  /// In en, this message translates to:
  /// **'This track can’t be saved offline'**
  String get ofCantSaveTrack;

  /// No description provided for @ofBusyWithAnother.
  ///
  /// In en, this message translates to:
  /// **'Already downloading another list'**
  String get ofBusyWithAnother;

  /// No description provided for @ofDownloadedAll.
  ///
  /// In en, this message translates to:
  /// **'Tracks downloaded: {count}'**
  String ofDownloadedAll(int count);

  /// No description provided for @ofDownloadedNone.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t download a single track'**
  String get ofDownloadedNone;

  /// No description provided for @ofDownloadedPartial.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {ok} of {total}, failed: {failed}'**
  String ofDownloadedPartial(int ok, int total, int failed);

  /// No description provided for @ofStreamOnly.
  ///
  /// In en, this message translates to:
  /// **'This track is stream-only — it can’t be saved'**
  String get ofStreamOnly;

  /// No description provided for @ofDrm.
  ///
  /// In en, this message translates to:
  /// **'The track is DRM-protected'**
  String get ofDrm;

  /// No description provided for @ofNoFileLink.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t return a file link'**
  String get ofNoFileLink;

  /// No description provided for @ofNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get ofNoConnection;

  /// No description provided for @ofSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save: {message}'**
  String ofSaveFailed(String message);

  /// No description provided for @fdPathIos.
  ///
  /// In en, this message translates to:
  /// **'Files → On My iPhone → Bloom'**
  String get fdPathIos;

  /// No description provided for @fdPathAndroid.
  ///
  /// In en, this message translates to:
  /// **'Music/Bloom'**
  String get fdPathAndroid;

  /// No description provided for @fdCantDownload.
  ///
  /// In en, this message translates to:
  /// **'This track can’t be downloaded'**
  String get fdCantDownload;

  /// No description provided for @fdNeedPermission.
  ///
  /// In en, this message translates to:
  /// **'Storage access is required — allow it and try again'**
  String get fdNeedPermission;

  /// No description provided for @fdSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the file'**
  String get fdSaveFailed;

  /// No description provided for @fdDownloadFile.
  ///
  /// In en, this message translates to:
  /// **'Download as a file'**
  String get fdDownloadFile;

  /// No description provided for @fdDownloadCover.
  ///
  /// In en, this message translates to:
  /// **'Download cover'**
  String get fdDownloadCover;

  /// No description provided for @fdDownloadingCover.
  ///
  /// In en, this message translates to:
  /// **'Downloading cover…'**
  String get fdDownloadingCover;

  /// desktop: lib.plmenu.convert
  ///
  /// In en, this message translates to:
  /// **'Transfer to source…'**
  String get tlConvert;

  /// desktop: lib.convert.title
  ///
  /// In en, this message translates to:
  /// **'Transfer to source'**
  String get cvTitle;

  /// No description provided for @cvScanning.
  ///
  /// In en, this message translates to:
  /// **'Looking up tracks on {source}…'**
  String cvScanning(String source);

  /// desktop: lib.convert.hint.scanning
  ///
  /// In en, this message translates to:
  /// **'You can leave — the transfer will be cancelled'**
  String get cvScanHint;

  /// No description provided for @cvSummary.
  ///
  /// In en, this message translates to:
  /// **'Moved {moved} · kept {kept} · skipped {skipped}'**
  String cvSummary(int moved, int kept, int skipped);

  /// desktop: lib.convert.takeBest
  ///
  /// In en, this message translates to:
  /// **'Take the best'**
  String get cvTakeBest;

  /// No description provided for @cvCreate.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Create a playlist of {count} track} other{Create a playlist of {count} tracks}}'**
  String cvCreate(int count);

  /// No description provided for @cvTagMoved.
  ///
  /// In en, this message translates to:
  /// **'Transferred'**
  String get cvTagMoved;

  /// No description provided for @cvTagOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get cvTagOriginal;

  /// No description provided for @cvTagOnTarget.
  ///
  /// In en, this message translates to:
  /// **'Already here'**
  String get cvTagOnTarget;

  /// No description provided for @cvTagSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get cvTagSkipped;

  /// No description provided for @cvNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found on {source}'**
  String cvNotFound(String source);

  /// No description provided for @cvSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t answer'**
  String get cvSearchFailed;

  /// No description provided for @cvKeepOriginal.
  ///
  /// In en, this message translates to:
  /// **'Keep the original'**
  String get cvKeepOriginal;

  /// No description provided for @cvSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip this track'**
  String get cvSkip;

  /// No description provided for @cvCreated.
  ///
  /// In en, this message translates to:
  /// **'“{name}” created — {tracks}'**
  String cvCreated(String name, String tracks);

  /// desktop: lib.ctx.switchSrc
  ///
  /// In en, this message translates to:
  /// **'Switch source'**
  String get spSwitch;

  /// No description provided for @spSearching.
  ///
  /// In en, this message translates to:
  /// **'Looking on {source}…'**
  String spSearching(String source);

  /// desktop: toast.srcNow
  ///
  /// In en, this message translates to:
  /// **'Now playing from {source}'**
  String spNow(String source);

  /// desktop: toast.trackNotOnSrc
  ///
  /// In en, this message translates to:
  /// **'This track isn’t on {source}'**
  String spNotFound(String source);

  /// desktop: toast.srcSwitchFail
  ///
  /// In en, this message translates to:
  /// **'The source didn’t answer — try again'**
  String get spFailed;

  /// desktop: toast.srcUnavailable
  ///
  /// In en, this message translates to:
  /// **'This source is unavailable'**
  String get spUnavailable;

  /// desktop: lib.plmenu.mergeWith
  ///
  /// In en, this message translates to:
  /// **'Merge with…'**
  String get tlMergeWith;

  /// No description provided for @mgTitle.
  ///
  /// In en, this message translates to:
  /// **'Merging playlists'**
  String get mgTitle;

  /// No description provided for @mgNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name of the new playlist'**
  String get mgNameHint;

  /// No description provided for @mgPickHint.
  ///
  /// In en, this message translates to:
  /// **'Pick what to merge in'**
  String get mgPickHint;

  /// No description provided for @mgResult.
  ///
  /// In en, this message translates to:
  /// **'You’ll get {tracks}'**
  String mgResult(String tracks);

  /// No description provided for @mgDupsDropped.
  ///
  /// In en, this message translates to:
  /// **'−{count} repeats'**
  String mgDupsDropped(int count);

  /// No description provided for @mgDedup.
  ///
  /// In en, this message translates to:
  /// **'Remove duplicates'**
  String get mgDedup;

  /// No description provided for @mgDeleteSources.
  ///
  /// In en, this message translates to:
  /// **'Delete the originals'**
  String get mgDeleteSources;

  /// No description provided for @mgNothingToMerge.
  ///
  /// In en, this message translates to:
  /// **'There is no other playlist to merge with'**
  String get mgNothingToMerge;

  /// No description provided for @mgMerged.
  ///
  /// In en, this message translates to:
  /// **'“{name}” collected — {tracks}'**
  String mgMerged(String name, String tracks);

  /// desktop: lib.plmenu.findDups
  ///
  /// In en, this message translates to:
  /// **'Find duplicates'**
  String get tlFindDups;

  /// desktop: lib.dups.title
  ///
  /// In en, this message translates to:
  /// **'Duplicate tracks'**
  String get dupsTitle;

  /// No description provided for @dupsFound.
  ///
  /// In en, this message translates to:
  /// **'{groups, plural, one{{groups} group} other{{groups} groups}} · {extra, plural, one{{extra} extra copy} other{{extra} extra copies}}'**
  String dupsFound(int groups, int extra);

  /// No description provided for @dupsChecked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} track checked} other{{count} tracks checked}}'**
  String dupsChecked(int count);

  /// No description provided for @dupsCopies.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} copy} other{{count} copies}}'**
  String dupsCopies(int count);

  /// No description provided for @dupsPlays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} play} other{{count} plays}}'**
  String dupsPlays(int count);

  /// No description provided for @dupsKeep.
  ///
  /// In en, this message translates to:
  /// **'keep'**
  String get dupsKeep;

  /// No description provided for @dupsNone.
  ///
  /// In en, this message translates to:
  /// **'No duplicates found'**
  String get dupsNone;

  /// desktop: lib.dups.delAll
  ///
  /// In en, this message translates to:
  /// **'Remove all'**
  String get dupsDelAll;

  /// desktop: lib.dups.delGroup
  ///
  /// In en, this message translates to:
  /// **'Remove copies'**
  String get dupsDelGroup;

  /// No description provided for @dupsRemoved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} copy removed} other{{count} copies removed}}'**
  String dupsRemoved(int count);

  /// desktop: lib.ctx.trackInfo
  ///
  /// In en, this message translates to:
  /// **'Track info'**
  String get tiTitle;

  /// No description provided for @tiAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get tiAlbum;

  /// No description provided for @tiYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get tiYear;

  /// No description provided for @tiReleased.
  ///
  /// In en, this message translates to:
  /// **'Release date'**
  String get tiReleased;

  /// No description provided for @setRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get setRelease;

  /// No description provided for @tiDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get tiDuration;

  /// No description provided for @tiPublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get tiPublisher;

  /// No description provided for @tiGenres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get tiGenres;

  /// No description provided for @tiDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get tiDescription;

  /// No description provided for @tiFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get tiFile;

  /// desktop: TrackInfoModal ti-credited — artist as credited by the source
  ///
  /// In en, this message translates to:
  /// **'Credited'**
  String get tiCredited;

  /// No description provided for @tiExplicit.
  ///
  /// In en, this message translates to:
  /// **'Explicit lyrics'**
  String get tiExplicit;

  /// No description provided for @tiNothing.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t share anything else about this track'**
  String get tiNothing;

  /// desktop: lib.ctx.toQueue
  ///
  /// In en, this message translates to:
  /// **'To queue'**
  String get taToQueue;

  /// desktop: lib.ctx.playNext
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get taPlayNext;

  /// desktop: player.aria.removeFromQueue
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get taRemoveFromQueue;

  /// desktop: lib.ctx.removeFromPl
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get taRemoveFromPlaylist;

  /// desktop: lib.ctx.download — flyout with the two kinds of download
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get taDownload;

  /// No description provided for @taRemoveFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from likes'**
  String get taRemoveFromFavorites;

  /// No description provided for @taAddToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get taAddToFavorites;

  /// No description provided for @taAddToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get taAddToPlaylist;

  /// desktop: player.dl.offline
  ///
  /// In en, this message translates to:
  /// **'Listen offline'**
  String get taListenOffline;

  /// desktop: player.dl.offlineRemove
  ///
  /// In en, this message translates to:
  /// **'Remove from offline'**
  String get taRemoveOffline;

  /// No description provided for @taGoToArtist.
  ///
  /// In en, this message translates to:
  /// **'Go to artist'**
  String get taGoToArtist;

  /// No description provided for @taDeleteTrack.
  ///
  /// In en, this message translates to:
  /// **'Delete track'**
  String get taDeleteTrack;

  /// No description provided for @taTrackDeleted.
  ///
  /// In en, this message translates to:
  /// **'Track deleted'**
  String get taTrackDeleted;

  /// No description provided for @taAddedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Added to library'**
  String get taAddedToLibrary;

  /// desktop: search.tab.all
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get searchTabAll;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchHint;

  /// desktop: search.allSources
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get searchSourceAll;

  /// desktop: search.recentQueries
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get searchRecent;

  /// desktop: search.recentOpened
  ///
  /// In en, this message translates to:
  /// **'Recently opened'**
  String get searchRecentOpened;

  /// No description provided for @searchRemoveRecent.
  ///
  /// In en, this message translates to:
  /// **'Remove from recent'**
  String get searchRemoveRecent;

  /// No description provided for @searchNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get searchNothingFound;

  /// No description provided for @searchFindSomething.
  ///
  /// In en, this message translates to:
  /// **'Find something'**
  String get searchFindSomething;

  /// No description provided for @searchSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing found in this section'**
  String get searchSectionEmpty;

  /// No description provided for @profileDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Listener'**
  String get profileDefaultName;

  /// No description provided for @profileNickCopied.
  ///
  /// In en, this message translates to:
  /// **'Nickname copied!'**
  String get profileNickCopied;

  /// desktop: ach.title
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get profileAchievements;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved!'**
  String get profileSaved;

  /// No description provided for @profileNickname.
  ///
  /// In en, this message translates to:
  /// **'NICKNAME'**
  String get profileNickname;

  /// No description provided for @profileNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a nickname...'**
  String get profileNicknameHint;

  /// No description provided for @profileAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get profileAbout;

  /// No description provided for @profileAboutHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself...'**
  String get profileAboutHint;

  /// No description provided for @profileStatus.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get profileStatus;

  /// No description provided for @profileStatusHint.
  ///
  /// In en, this message translates to:
  /// **'\"My status...\"'**
  String get profileStatusHint;

  /// No description provided for @profileColorSolid.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get profileColorSolid;

  /// No description provided for @profileColorAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get profileColorAuto;

  /// No description provided for @profileColorGradient.
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get profileColorGradient;

  /// No description provided for @profileAutoHint.
  ///
  /// In en, this message translates to:
  /// **'The colour of your most played track\'s cover'**
  String get profileAutoHint;

  /// No description provided for @profileSince.
  ///
  /// In en, this message translates to:
  /// **'With us since {date}'**
  String profileSince(String date);

  /// desktop: profile.sum.plays
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{play} other{plays}}'**
  String profileSumPlays(int count);

  /// No description provided for @profileSumTime.
  ///
  /// In en, this message translates to:
  /// **'listened'**
  String get profileSumTime;

  /// No description provided for @profileSumStreak.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{day in a row} other{days in a row}}'**
  String profileSumStreak(int count);

  /// No description provided for @profileSumArtists.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{artist} other{artists}}'**
  String profileSumArtists(int count);

  /// No description provided for @profileEntryStats.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get profileEntryStats;

  /// No description provided for @profileEntryOf.
  ///
  /// In en, this message translates to:
  /// **'of {total}'**
  String profileEntryOf(int total);

  /// No description provided for @profileActivityDays.
  ///
  /// In en, this message translates to:
  /// **'last 30 days'**
  String get profileActivityDays;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Tracks you listen to will show up here'**
  String get historyEmpty;

  /// No description provided for @profileRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get profileRemoveImage;

  /// No description provided for @profileRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get profileRemovePhoto;

  /// No description provided for @profileZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom  {percent}%'**
  String profileZoom(int percent);

  /// desktop: ach.unlocked
  ///
  /// In en, this message translates to:
  /// **'🏅 Achievement unlocked: {name} — {tier}'**
  String achUnlockedToast(String name, String tier);

  /// No description provided for @achMax.
  ///
  /// In en, this message translates to:
  /// **'Maxed out'**
  String get achMax;

  /// No description provided for @achUnlockedAt.
  ///
  /// In en, this message translates to:
  /// **'earned {date}'**
  String achUnlockedAt(String date);

  /// No description provided for @achTierBronze.
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get achTierBronze;

  /// No description provided for @achTierSilver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get achTierSilver;

  /// No description provided for @achTierGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get achTierGold;

  /// No description provided for @achListenerName.
  ///
  /// In en, this message translates to:
  /// **'Music Lover'**
  String get achListenerName;

  /// No description provided for @achListenerDesc.
  ///
  /// In en, this message translates to:
  /// **'Total plays'**
  String get achListenerDesc;

  /// No description provided for @achTimeName.
  ///
  /// In en, this message translates to:
  /// **'In the Headphones'**
  String get achTimeName;

  /// No description provided for @achTimeDesc.
  ///
  /// In en, this message translates to:
  /// **'Listening time'**
  String get achTimeDesc;

  /// No description provided for @achStreakName.
  ///
  /// In en, this message translates to:
  /// **'On a Roll'**
  String get achStreakName;

  /// No description provided for @achStreakDesc.
  ///
  /// In en, this message translates to:
  /// **'Days in a row with plays'**
  String get achStreakDesc;

  /// No description provided for @achMarathonName.
  ///
  /// In en, this message translates to:
  /// **'Marathoner'**
  String get achMarathonName;

  /// No description provided for @achMarathonDesc.
  ///
  /// In en, this message translates to:
  /// **'Tracks in a single day'**
  String get achMarathonDesc;

  /// No description provided for @achVeteranName.
  ///
  /// In en, this message translates to:
  /// **'Bloom Veteran'**
  String get achVeteranName;

  /// No description provided for @achVeteranDesc.
  ///
  /// In en, this message translates to:
  /// **'Time in the app'**
  String get achVeteranDesc;

  /// No description provided for @achDevoteeName.
  ///
  /// In en, this message translates to:
  /// **'Devotion'**
  String get achDevoteeName;

  /// No description provided for @achDevoteeDesc.
  ///
  /// In en, this message translates to:
  /// **'Active days total'**
  String get achDevoteeDesc;

  /// No description provided for @statsTracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get statsTracks;

  /// No description provided for @statsPlays.
  ///
  /// In en, this message translates to:
  /// **'Plays'**
  String get statsPlays;

  /// No description provided for @statsTime.
  ///
  /// In en, this message translates to:
  /// **'Listening time'**
  String get statsTime;

  /// No description provided for @statsUnique.
  ///
  /// In en, this message translates to:
  /// **'Unique'**
  String get statsUnique;

  /// No description provided for @statsAvgLength.
  ///
  /// In en, this message translates to:
  /// **'Average length'**
  String get statsAvgLength;

  /// No description provided for @statsFavArtist.
  ///
  /// In en, this message translates to:
  /// **'Favorite artist'**
  String get statsFavArtist;

  /// No description provided for @statsAppTime.
  ///
  /// In en, this message translates to:
  /// **'Time in app'**
  String get statsAppTime;

  /// No description provided for @statsRecordDay.
  ///
  /// In en, this message translates to:
  /// **'Day record'**
  String get statsRecordDay;

  /// No description provided for @statsHoursDay.
  ///
  /// In en, this message translates to:
  /// **'hours/day'**
  String get statsHoursDay;

  /// No description provided for @statsTracksDay.
  ///
  /// In en, this message translates to:
  /// **'tracks/day'**
  String get statsTracksDay;

  /// No description provided for @statsArtists.
  ///
  /// In en, this message translates to:
  /// **'artists'**
  String get statsArtists;

  /// No description provided for @statsSources.
  ///
  /// In en, this message translates to:
  /// **'Where you listen most'**
  String get statsSources;

  /// No description provided for @statsTopTracks.
  ///
  /// In en, this message translates to:
  /// **'Top tracks'**
  String get statsTopTracks;

  /// profile: favorite artists strip
  ///
  /// In en, this message translates to:
  /// **'Top artists'**
  String get statsTopArtists;

  /// profile: stats overview grid
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get statsOverview;

  /// No description provided for @statsNoDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get statsNoDataYet;

  /// No description provided for @statsCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get statsCopy;

  /// No description provided for @statsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get statsClear;

  /// No description provided for @statsClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the statistics?'**
  String get statsClearTitle;

  /// No description provided for @statsClearSub.
  ///
  /// In en, this message translates to:
  /// **'Plays, history, activity and achievements will be deleted'**
  String get statsClearSub;

  /// No description provided for @statsClearLevel.
  ///
  /// In en, this message translates to:
  /// **'Reset the level too'**
  String get statsClearLevel;

  /// No description provided for @levelTitle.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String levelTitle(int level);

  /// No description provided for @levelDesc.
  ///
  /// In en, this message translates to:
  /// **'Your level grows as you listen to music and come back to Bloom'**
  String get levelDesc;

  /// No description provided for @levelXp.
  ///
  /// In en, this message translates to:
  /// **'{into} / {span} XP'**
  String levelXp(String into, String span);

  /// No description provided for @levelToNext.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to level {level}'**
  String levelToNext(int level, String xp);

  /// No description provided for @levelTracks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{≈ {count} track} other{≈ {count} tracks}}'**
  String levelTracks(int count);

  /// No description provided for @levelHow.
  ///
  /// In en, this message translates to:
  /// **'How it grows'**
  String get levelHow;

  /// No description provided for @levelPlays.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get levelPlays;

  /// No description provided for @levelPlaysSub.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP a track'**
  String levelPlaysSub(int xp);

  /// No description provided for @levelDays.
  ///
  /// In en, this message translates to:
  /// **'Daily visits'**
  String get levelDays;

  /// No description provided for @levelDaysSub.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP a day, more for days in a row'**
  String levelDaysSub(int xp);

  /// No description provided for @levelAch.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get levelAch;

  /// No description provided for @levelAchSub.
  ///
  /// In en, this message translates to:
  /// **'+{bronze} / {silver} / {gold} XP for bronze, silver and gold'**
  String levelAchSub(int bronze, int silver, int gold);

  /// No description provided for @levelBanked.
  ///
  /// In en, this message translates to:
  /// **'Earlier stats'**
  String get levelBanked;

  /// No description provided for @levelBankedSub.
  ///
  /// In en, this message translates to:
  /// **'Kept when the stats were cleared'**
  String get levelBankedSub;

  /// No description provided for @levelOk.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get levelOk;

  /// No description provided for @statsCopied.
  ///
  /// In en, this message translates to:
  /// **'Statistics copied'**
  String get statsCopied;

  /// No description provided for @statsCleared.
  ///
  /// In en, this message translates to:
  /// **'Statistics cleared'**
  String get statsCleared;

  /// No description provided for @statsZeroMinutes.
  ///
  /// In en, this message translates to:
  /// **'0 min'**
  String get statsZeroMinutes;

  /// No description provided for @statsHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String statsHoursMinutes(int hours, int minutes);

  /// No description provided for @statsMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String statsMinutes(int minutes);

  /// No description provided for @statsShareTitle.
  ///
  /// In en, this message translates to:
  /// **'🎵 My Bloom stats'**
  String get statsShareTitle;

  /// No description provided for @statsShareTracks.
  ///
  /// In en, this message translates to:
  /// **'📚 Tracks: {count}'**
  String statsShareTracks(int count);

  /// No description provided for @statsShareUnique.
  ///
  /// In en, this message translates to:
  /// **'🎵 Unique: {count}'**
  String statsShareUnique(int count);

  /// No description provided for @statsSharePlays.
  ///
  /// In en, this message translates to:
  /// **'▶️ Played: {count}'**
  String statsSharePlays(int count);

  /// No description provided for @statsShareTime.
  ///
  /// In en, this message translates to:
  /// **'🎧 Listening time: {value}'**
  String statsShareTime(String value);

  /// No description provided for @statsShareAvgLength.
  ///
  /// In en, this message translates to:
  /// **'📏 Average length: {value}'**
  String statsShareAvgLength(String value);

  /// No description provided for @statsShareAppTime.
  ///
  /// In en, this message translates to:
  /// **'⏱️ Time in app: {value}'**
  String statsShareAppTime(String value);

  /// No description provided for @statsShareFavArtist.
  ///
  /// In en, this message translates to:
  /// **'⭐ Favorite artist: {name}'**
  String statsShareFavArtist(String name);

  /// No description provided for @statsShareRecordDay.
  ///
  /// In en, this message translates to:
  /// **'🏆 Day record: {count}'**
  String statsShareRecordDay(int count);

  /// No description provided for @statsShareAvgPerDay.
  ///
  /// In en, this message translates to:
  /// **'📈 Daily average:'**
  String get statsShareAvgPerDay;

  /// No description provided for @statsShareSources.
  ///
  /// In en, this message translates to:
  /// **'📡 Where you listened most:'**
  String get statsShareSources;

  /// No description provided for @statsShareTopTracks.
  ///
  /// In en, this message translates to:
  /// **'🔥 Top tracks:'**
  String get statsShareTopTracks;

  /// No description provided for @statsShareTopArtists.
  ///
  /// In en, this message translates to:
  /// **'👤 Top artists:'**
  String get statsShareTopArtists;

  /// desktop: settings.nav.group.main
  ///
  /// In en, this message translates to:
  /// **'APP'**
  String get setGroupApp;

  /// desktop: settings.nav.group.appearance
  ///
  /// In en, this message translates to:
  /// **'INTERFACE'**
  String get setGroupInterface;

  /// desktop: settings.nav.group.integrations
  ///
  /// In en, this message translates to:
  /// **'INTEGRATIONS'**
  String get setGroupIntegrations;

  /// desktop: settings.nav.system
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get setSystem;

  /// desktop: settings.nav.audio
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get setAudio;

  /// No description provided for @setSwipes.
  ///
  /// In en, this message translates to:
  /// **'Swipes'**
  String get setSwipes;

  /// No description provided for @setLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get setLanguage;

  /// desktop: settings.nav.storage
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get setStorage;

  /// desktop: settings.nav.player
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get setPlayer;

  /// desktop: settings.nav.interface
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get setAppearance;

  /// desktop: settings.view.miniPlayer
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get setMiniPlayer;

  /// desktop: settings.view.titleAlign — the group holding it
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get pvGroupTitle;

  /// desktop: settings.view.titleAlign
  ///
  /// In en, this message translates to:
  /// **'Title alignment'**
  String get pvTitleAlign;

  /// No description provided for @pvTitleAlignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get pvTitleAlignLeft;

  /// No description provided for @pvTitleAlignLeftSub.
  ///
  /// In en, this message translates to:
  /// **'title on the left'**
  String get pvTitleAlignLeftSub;

  /// No description provided for @pvTitleAlignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get pvTitleAlignCenter;

  /// No description provided for @pvTitleAlignCenterSub.
  ///
  /// In en, this message translates to:
  /// **'title centered'**
  String get pvTitleAlignCenterSub;

  /// No description provided for @pvTitleAlignRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get pvTitleAlignRight;

  /// No description provided for @pvTitleAlignRightSub.
  ///
  /// In en, this message translates to:
  /// **'title on the right'**
  String get pvTitleAlignRightSub;

  /// the group holding the player style row
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get pvGroupLook;

  /// desktop: settings.view.style
  ///
  /// In en, this message translates to:
  /// **'Player style'**
  String get pvStyleRow;

  /// desktop: settings.view.style.standard
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get pvStyleStandard;

  /// No description provided for @pvStyleStandardSub.
  ///
  /// In en, this message translates to:
  /// **'the classic look with a square cover'**
  String get pvStyleStandardSub;

  /// desktop: settings.view.style.vinyl
  ///
  /// In en, this message translates to:
  /// **'Vinyl'**
  String get pvStyleVinyl;

  /// No description provided for @pvStyleVinylSub.
  ///
  /// In en, this message translates to:
  /// **'a spinning vinyl record'**
  String get pvStyleVinylSub;

  /// shape of the play/pause button in the player and the mini player
  ///
  /// In en, this message translates to:
  /// **'Play button'**
  String get pvPlayButtonRow;

  /// No description provided for @pvPlayButtonCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get pvPlayButtonCircle;

  /// No description provided for @pvPlayButtonCircleSub.
  ///
  /// In en, this message translates to:
  /// **'accent fill, as it is now'**
  String get pvPlayButtonCircleSub;

  /// No description provided for @pvPlayButtonSquare.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get pvPlayButtonSquare;

  /// No description provided for @pvPlayButtonSquareSub.
  ///
  /// In en, this message translates to:
  /// **'the same fill with rounded corners'**
  String get pvPlayButtonSquareSub;

  /// No description provided for @pvPlayButtonPlain.
  ///
  /// In en, this message translates to:
  /// **'No background'**
  String get pvPlayButtonPlain;

  /// No description provided for @pvPlayButtonPlainSub.
  ///
  /// In en, this message translates to:
  /// **'icon only, larger than its neighbours'**
  String get pvPlayButtonPlainSub;

  /// the group holding the slider type row
  ///
  /// In en, this message translates to:
  /// **'Slider'**
  String get pvGroupSlider;

  /// desktop: settings.view.slider
  ///
  /// In en, this message translates to:
  /// **'Slider type'**
  String get pvSliderRow;

  /// desktop: settings.view.slider.default
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get pvSliderStandard;

  /// desktop: settings.view.slider.thin
  ///
  /// In en, this message translates to:
  /// **'Thin'**
  String get pvSliderThin;

  /// desktop: settings.view.slider.wave
  ///
  /// In en, this message translates to:
  /// **'Wave'**
  String get pvSliderWave;

  /// desktop: settings.view.lyrics
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get pvGroupLyrics;

  /// settings row that opens the lyrics style sheet
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get pvLyricsRow;

  /// No description provided for @pvLyricsMode.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get pvLyricsMode;

  /// No description provided for @pvLyricsModeSub.
  ///
  /// In en, this message translates to:
  /// **'where the cover goes once lyrics are on'**
  String get pvLyricsModeSub;

  /// No description provided for @pvLyricsModeOverlay.
  ///
  /// In en, this message translates to:
  /// **'Over the cover'**
  String get pvLyricsModeOverlay;

  /// No description provided for @pvLyricsModeReplace.
  ///
  /// In en, this message translates to:
  /// **'Instead of the cover'**
  String get pvLyricsModeReplace;

  /// desktop: settings.view.queueView — the group holding the queue view cards
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get pvGroupQueue;

  /// desktop: settings.view.queueView.normal
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get pvQueueNormal;

  /// desktop: settings.view.queueView.extended
  ///
  /// In en, this message translates to:
  /// **'Extended'**
  String get pvQueueExtended;

  /// toggle: show the «Up next» pill under the player slider; mobile-only, no desktop counterpart
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get pvNextUp;

  /// subtitle of the pvNextUp toggle
  ///
  /// In en, this message translates to:
  /// **'A pill under the slider with what plays next'**
  String get pvNextUpSub;

  /// the group holding the full-screen player background row; mobile-only, no desktop counterpart
  ///
  /// In en, this message translates to:
  /// **'Player background'**
  String get pvGroupBg;

  /// No description provided for @pvBgRow.
  ///
  /// In en, this message translates to:
  /// **'Player background'**
  String get pvBgRow;

  /// No description provided for @pvBgCover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get pvBgCover;

  /// No description provided for @pvBgCoverSub.
  ///
  /// In en, this message translates to:
  /// **'The track cover, full screen'**
  String get pvBgCoverSub;

  /// player background option: the picture set as the app background in Customization
  ///
  /// In en, this message translates to:
  /// **'App background'**
  String get pvBgApp;

  /// No description provided for @pvBgAppSub.
  ///
  /// In en, this message translates to:
  /// **'The picture set as the app background'**
  String get pvBgAppSub;

  /// shown instead of pvBgAppSub while the option is greyed out — no picture is set as the app background
  ///
  /// In en, this message translates to:
  /// **'Set a picture as the background in Customization first'**
  String get pvBgAppOff;

  /// No description provided for @pvBgColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get pvBgColor;

  /// No description provided for @pvBgColorSub.
  ///
  /// In en, this message translates to:
  /// **'Adaptive gradient from the cover'**
  String get pvBgColorSub;

  /// No description provided for @pvBgNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvBgNone;

  /// No description provided for @pvBgNoneSub.
  ///
  /// In en, this message translates to:
  /// **'No background'**
  String get pvBgNoneSub;

  /// row shown under pvBgRow only while the player background is the track cover; mobile-only, no desktop counterpart
  ///
  /// In en, this message translates to:
  /// **'Cover background effect'**
  String get pvBgFxRow;

  /// No description provided for @pvBgFxDim.
  ///
  /// In en, this message translates to:
  /// **'Dim'**
  String get pvBgFxDim;

  /// No description provided for @pvBgFxDimSub.
  ///
  /// In en, this message translates to:
  /// **'Sharp cover under a soft dim'**
  String get pvBgFxDimSub;

  /// No description provided for @pvBgFxBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get pvBgFxBlur;

  /// No description provided for @pvBgFxBlurSub.
  ///
  /// In en, this message translates to:
  /// **'Deeply blurred cover'**
  String get pvBgFxBlurSub;

  /// No description provided for @pvBgFxOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get pvBgFxOriginal;

  /// No description provided for @pvBgFxOriginalSub.
  ///
  /// In en, this message translates to:
  /// **'Clean cover, no filters'**
  String get pvBgFxOriginalSub;

  /// No description provided for @pvGroupMiniControls.
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get pvGroupMiniControls;

  /// desktop: settings.view.mpBg
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get pvMiniBgRow;

  /// No description provided for @pvMiniBgSub.
  ///
  /// In en, this message translates to:
  /// **'what fills the card above the tab bar'**
  String get pvMiniBgSub;

  /// No description provided for @pvMiniBgTheme.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get pvMiniBgTheme;

  /// No description provided for @pvMiniBgCoverColor.
  ///
  /// In en, this message translates to:
  /// **'Cover color'**
  String get pvMiniBgCoverColor;

  /// No description provided for @pvMiniBgCover.
  ///
  /// In en, this message translates to:
  /// **'The cover itself'**
  String get pvMiniBgCover;

  /// desktop: settings.view.mpProgress
  ///
  /// In en, this message translates to:
  /// **'Progress indicators'**
  String get pvMiniProgressRow;

  /// No description provided for @pvMiniProgressSub.
  ///
  /// In en, this message translates to:
  /// **'several can be on at once'**
  String get pvMiniProgressSub;

  /// No description provided for @pvMiniProgressNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvMiniProgressNone;

  /// No description provided for @pvMiniProgressLine.
  ///
  /// In en, this message translates to:
  /// **'Line at the bottom'**
  String get pvMiniProgressLine;

  /// No description provided for @pvMiniProgressFill.
  ///
  /// In en, this message translates to:
  /// **'Background fill'**
  String get pvMiniProgressFill;

  /// No description provided for @pvMiniProgressRing.
  ///
  /// In en, this message translates to:
  /// **'Ring around the cover'**
  String get pvMiniProgressRing;

  /// desktop: settings.view.mpCoverShape
  ///
  /// In en, this message translates to:
  /// **'Cover shape'**
  String get pvMiniShapeRow;

  /// No description provided for @pvMiniShapeRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get pvMiniShapeRounded;

  /// No description provided for @pvMiniShapeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get pvMiniShapeCircle;

  /// desktop: settings.view.mpRounded
  ///
  /// In en, this message translates to:
  /// **'Corner rounding'**
  String get pvMiniRadiusRow;

  /// No description provided for @pvMiniRadiusNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvMiniRadiusNone;

  /// No description provided for @pvMiniRadiusSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get pvMiniRadiusSoft;

  /// No description provided for @pvMiniRadiusRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get pvMiniRadiusRounded;

  /// No description provided for @pvMiniRadiusPill.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get pvMiniRadiusPill;

  /// desktop: settings.view.mpHide
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get pvMiniButtonsRow;

  /// No description provided for @pvMiniButtonsSub.
  ///
  /// In en, this message translates to:
  /// **'what stands in the row right of the title'**
  String get pvMiniButtonsSub;

  /// No description provided for @pvMiniButtonsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvMiniButtonsNone;

  /// No description provided for @pvMiniButtonPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get pvMiniButtonPrev;

  /// No description provided for @pvMiniButtonPlay.
  ///
  /// In en, this message translates to:
  /// **'Play/Pause'**
  String get pvMiniButtonPlay;

  /// No description provided for @pvMiniButtonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get pvMiniButtonNext;

  /// No description provided for @pvMiniButtonFav.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get pvMiniButtonFav;

  /// No description provided for @pvMiniNeighborsRow.
  ///
  /// In en, this message translates to:
  /// **'Adjacent tracks'**
  String get pvMiniNeighborsRow;

  /// No description provided for @pvMiniNeighborsSub.
  ///
  /// In en, this message translates to:
  /// **'the previous and next cards peek at the edges, and a swipe across the card flips through the queue'**
  String get pvMiniNeighborsSub;

  /// No description provided for @pvMiniNeighborsOff.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get pvMiniNeighborsOff;

  /// No description provided for @pvMiniNeighborsOn.
  ///
  /// In en, this message translates to:
  /// **'Peeking at the edges'**
  String get pvMiniNeighborsOn;

  /// desktop: lyrics.loading
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics…'**
  String get lyricsLoading;

  /// desktop: lyrics.notFound
  ///
  /// In en, this message translates to:
  /// **'Lyrics not found'**
  String get lyricsNotFound;

  /// No description provided for @swZoneLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get swZoneLibrary;

  /// No description provided for @swZoneQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get swZoneQueue;

  /// No description provided for @swZoneMini.
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get swZoneMini;

  /// No description provided for @swZonePlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get swZonePlayer;

  /// No description provided for @swLeft.
  ///
  /// In en, this message translates to:
  /// **'Swipe left'**
  String get swLeft;

  /// No description provided for @swRight.
  ///
  /// In en, this message translates to:
  /// **'Swipe right'**
  String get swRight;

  /// No description provided for @swActNone.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get swActNone;

  /// No description provided for @swActLike.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get swActLike;

  /// No description provided for @swActQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get swActQueue;

  /// desktop: lib.ctx.playNext — insert right after the current track
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get swActPlayNext;

  /// No description provided for @swActNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get swActNext;

  /// No description provided for @swActPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get swActPrev;

  /// No description provided for @swActDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get swActDownload;

  /// No description provided for @swActDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get swActDelete;

  /// No description provided for @swAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get swAddedToQueue;

  /// No description provided for @swAlreadyInQueue.
  ///
  /// In en, this message translates to:
  /// **'Already in the queue'**
  String get swAlreadyInQueue;

  /// No description provided for @swPlaysNext.
  ///
  /// In en, this message translates to:
  /// **'Plays next'**
  String get swPlaysNext;

  /// No description provided for @swLiked.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get swLiked;

  /// No description provided for @swUnliked.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get swUnliked;

  /// No description provided for @swRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get swRemoved;

  /// No description provided for @apLanguageRu.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get apLanguageRu;

  /// No description provided for @apLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get apLanguageEn;

  /// desktop: settings.interface.cat.theme
  ///
  /// In en, this message translates to:
  /// **'THEME'**
  String get apTheme;

  /// row that opens the theme picker sheet
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get apThemeRow;

  /// desktop: theme.ownName — title of the theme creator sheet
  ///
  /// In en, this message translates to:
  /// **'Custom theme'**
  String get thNew;

  /// desktop: theme.defaultName
  ///
  /// In en, this message translates to:
  /// **'My theme'**
  String get thNameDefault;

  /// desktop: theme.slot.bg
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get thSlotBg;

  /// desktop: theme.slot.card
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get thSlotCard;

  /// desktop: theme.slot.accent
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get thSlotAccent;

  /// desktop: theme.random
  ///
  /// In en, this message translates to:
  /// **'Random colors'**
  String get thRandom;

  /// desktop: theme.toast.created
  ///
  /// In en, this message translates to:
  /// **'Theme “{name}” created'**
  String thCreated(String name);

  /// desktop: theme.toast.deleted
  ///
  /// In en, this message translates to:
  /// **'Preset deleted'**
  String get thDeleted;

  /// desktop: theme.auto.name
  ///
  /// In en, this message translates to:
  /// **'Auto theme'**
  String get thAutoName;

  /// desktop: theme.auto.card — label of the auto theme card in the picker
  ///
  /// In en, this message translates to:
  /// **'Match track cover'**
  String get thAutoCard;

  /// desktop: settings.interface.autoAccent.title
  ///
  /// In en, this message translates to:
  /// **'Auto accent'**
  String get apAutoAccent;

  /// desktop: settings.interface.autoAccent.sub
  ///
  /// In en, this message translates to:
  /// **'Accent color from the track cover'**
  String get apAutoAccentSub;

  /// desktop: settings.interface.autoAccent.level
  ///
  /// In en, this message translates to:
  /// **'Accent brightness'**
  String get apAutoAccentLevel;

  /// desktop: settings.custom.tabs.bg
  ///
  /// In en, this message translates to:
  /// **'BACKGROUND'**
  String get apBgGroup;

  /// desktop: settings.interface.accentBadges.title
  ///
  /// In en, this message translates to:
  /// **'Badges in accent color'**
  String get apBadgesTitle;

  /// desktop: settings.interface.accentBadges.sub
  ///
  /// In en, this message translates to:
  /// **'Source badges use their brand colors by default; enable to tint them with the accent'**
  String get apBadgesSubtitle;

  /// phone only: the desktop app navigates from a sidebar
  ///
  /// In en, this message translates to:
  /// **'TAB BAR'**
  String get apNavBar;

  /// No description provided for @apNavBarRow.
  ///
  /// In en, this message translates to:
  /// **'Tab bar'**
  String get apNavBarRow;

  /// No description provided for @apNavBarPlain.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get apNavBarPlain;

  /// No description provided for @apNavBarRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded top'**
  String get apNavBarRounded;

  /// No description provided for @apNavBarDome.
  ///
  /// In en, this message translates to:
  /// **'Dome'**
  String get apNavBarDome;

  /// No description provided for @apNavBarFloating.
  ///
  /// In en, this message translates to:
  /// **'Floating'**
  String get apNavBarFloating;

  /// No description provided for @apNavBarPill.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get apNavBarPill;

  /// No description provided for @apNavTabsRow.
  ///
  /// In en, this message translates to:
  /// **'Tab order'**
  String get apNavTabsRow;

  /// No description provided for @apNavTabsDrag.
  ///
  /// In en, this message translates to:
  /// **'Drag a tab by its handle to change its place in the bar'**
  String get apNavTabsDrag;

  /// No description provided for @apNavMarkRow.
  ///
  /// In en, this message translates to:
  /// **'Active tab mark'**
  String get apNavMarkRow;

  /// No description provided for @apNavMarkNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get apNavMarkNone;

  /// No description provided for @apNavMarkPill.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get apNavMarkPill;

  /// No description provided for @apNavMarkDot.
  ///
  /// In en, this message translates to:
  /// **'Dot'**
  String get apNavMarkDot;

  /// No description provided for @apNavMarkLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get apNavMarkLine;

  /// No description provided for @apNavLabelsRow.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get apNavLabelsRow;

  /// No description provided for @apNavLabelsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get apNavLabelsNone;

  /// No description provided for @apNavLabelsAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get apNavLabelsAlways;

  /// No description provided for @apNavLabelsActive.
  ///
  /// In en, this message translates to:
  /// **'Active tab only'**
  String get apNavLabelsActive;

  /// desktop: settings.interface.nav.homeLogo.title
  ///
  /// In en, this message translates to:
  /// **'Logo instead of Home'**
  String get apNavHomeLogoRow;

  /// desktop: settings.interface.nav.homeLogo.sub
  ///
  /// In en, this message translates to:
  /// **'Show the Bloom mark in place of the Home tab icon'**
  String get apNavHomeLogoSub;

  /// No description provided for @scHelp.
  ///
  /// In en, this message translates to:
  /// **'Usually not needed: the key is picked up automatically — by scraping the site, and failing that by trying known ones. Setting your own makes sense if SoundCloud stopped responding.'**
  String get scHelp;

  /// No description provided for @scHint.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get scHint;

  /// No description provided for @scCheckConnection.
  ///
  /// In en, this message translates to:
  /// **'Check connection'**
  String get scCheckConnection;

  /// No description provided for @scConnectionOk.
  ///
  /// In en, this message translates to:
  /// **'Connection works'**
  String get scConnectionOk;

  /// No description provided for @scConnectionFail.
  ///
  /// In en, this message translates to:
  /// **'Not responding'**
  String get scConnectionFail;

  /// No description provided for @scActiveKey.
  ///
  /// In en, this message translates to:
  /// **'Active key'**
  String get scActiveKey;

  /// No description provided for @scSetup.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get scSetup;

  /// No description provided for @scReconfigure.
  ///
  /// In en, this message translates to:
  /// **'Reconfigure'**
  String get scReconfigure;

  /// No description provided for @scStatusAuto.
  ///
  /// In en, this message translates to:
  /// **'The key is picked up automatically'**
  String get scStatusAuto;

  /// No description provided for @scStatusManual.
  ///
  /// In en, this message translates to:
  /// **'Running on your own client_id'**
  String get scStatusManual;

  /// desktop: settings.sc.help.title
  ///
  /// In en, this message translates to:
  /// **'How to get a client_id'**
  String get scGuideTitle;

  /// No description provided for @scGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Step-by-step guide — usually not needed'**
  String get scGuideSubtitle;

  /// desktop: settings.sc.step1.* (**bold** marks what to look for)
  ///
  /// In en, this message translates to:
  /// **'Open **soundcloud.com** in a desktop browser'**
  String get scStep1;

  /// No description provided for @scStep2.
  ///
  /// In en, this message translates to:
  /// **'Press **F12** → the **Network** tab'**
  String get scStep2;

  /// No description provided for @scStep3.
  ///
  /// In en, this message translates to:
  /// **'Press play on any track'**
  String get scStep3;

  /// No description provided for @scStep4.
  ///
  /// In en, this message translates to:
  /// **'Find the request to **api-v2.soundcloud.com**'**
  String get scStep4;

  /// No description provided for @scStep5.
  ///
  /// In en, this message translates to:
  /// **'Copy the **client_id** parameter from the URL'**
  String get scStep5;

  /// desktop: settings.ym.checking
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get ymChecking;

  /// desktop: settings.ym.connected
  ///
  /// In en, this message translates to:
  /// **'✓ Connected'**
  String get ymConnected;

  /// desktop: settings.ym.notConnected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get ymNotConnected;

  /// desktop: settings.ym.logout
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get ymLogout;

  /// desktop: settings.ym.plus.active.a
  ///
  /// In en, this message translates to:
  /// **'Yandex Plus active'**
  String get ymPlusActiveA;

  /// desktop: settings.ym.plus.active.b
  ///
  /// In en, this message translates to:
  /// **'— tracks play directly from Yandex.'**
  String get ymPlusActiveB;

  /// desktop: settings.ym.plus.none.a
  ///
  /// In en, this message translates to:
  /// **'No Plus'**
  String get ymPlusNoneA;

  /// desktop: settings.ym.plus.none.b
  ///
  /// In en, this message translates to:
  /// **'— some tracks may be unavailable for playback.'**
  String get ymPlusNoneB;

  /// desktop: settings.ym.plus.unknown
  ///
  /// In en, this message translates to:
  /// **'Subscription status unknown.'**
  String get ymPlusUnknown;

  /// desktop: settings.ym.connect
  ///
  /// In en, this message translates to:
  /// **'Connect Yandex Music'**
  String get ymConnect;

  /// desktop: settings.ym.codePrompt.a
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get ymCodePromptA;

  /// desktop: settings.ym.codePrompt.b
  ///
  /// In en, this message translates to:
  /// **'and enter the code:'**
  String get ymCodePromptB;

  /// No description provided for @ymOpenPage.
  ///
  /// In en, this message translates to:
  /// **'Open the page'**
  String get ymOpenPage;

  /// No description provided for @ymCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get ymCodeCopied;

  /// desktop: ym.auth.gettingCode
  ///
  /// In en, this message translates to:
  /// **'Getting code…'**
  String get ymGettingCode;

  /// desktop: ym.auth.waiting
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation…'**
  String get ymWaiting;

  /// desktop: ym.auth.codeExpired
  ///
  /// In en, this message translates to:
  /// **'Code expired — press “Connect” again.'**
  String get ymCodeExpired;

  /// No description provided for @ymErrAuth.
  ///
  /// In en, this message translates to:
  /// **'Yandex Music token is invalid — sign in again'**
  String get ymErrAuth;

  /// No description provided for @ymErrNeedPlus.
  ///
  /// In en, this message translates to:
  /// **'Track unavailable — Yandex Plus subscription required'**
  String get ymErrNeedPlus;

  /// No description provided for @ymErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Yandex is not responding'**
  String get ymErrNetwork;

  /// No description provided for @ymGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'How to connect Yandex Music'**
  String get ymGuideTitle;

  /// No description provided for @ymGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Yandex ID — four steps'**
  String get ymGuideSubtitle;

  /// No description provided for @ymStep1.
  ///
  /// In en, this message translates to:
  /// **'Press **Connect Yandex Music**'**
  String get ymStep1;

  /// No description provided for @ymStep2.
  ///
  /// In en, this message translates to:
  /// **'The **ya.ru/device** page opens — sign in to your account'**
  String get ymStep2;

  /// No description provided for @ymStep3.
  ///
  /// In en, this message translates to:
  /// **'Enter the code Bloom shows (tap the code to copy it)'**
  String get ymStep3;

  /// No description provided for @ymStep4.
  ///
  /// In en, this message translates to:
  /// **'Come back to the app — the connection is picked up on its own'**
  String get ymStep4;

  /// No description provided for @ymGuideNote.
  ///
  /// In en, this message translates to:
  /// **'Without a Yandex Plus subscription some tracks won\'t play — those can be listened to from other platforms.'**
  String get ymGuideNote;

  /// desktop: settings.ytm.status
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get ytmConfigured;

  /// desktop: settings.ytm.noAuth
  ///
  /// In en, this message translates to:
  /// **'No authentication needed for now'**
  String get ytmNoAuth;

  /// desktop: settings.ytm.help (без запасного пути через SoundCloud — в мобилке бриджа нет)
  ///
  /// In en, this message translates to:
  /// **'Search, pages and link import work without auth. Playback and downloads come straight from YouTube.'**
  String get ytmHelp;

  /// No description provided for @ytmGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'What already works'**
  String get ytmGuideTitle;

  /// No description provided for @ytmGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to connect'**
  String get ytmGuideSubtitle;

  /// No description provided for @ytmStep1.
  ///
  /// In en, this message translates to:
  /// **'Search, artist, album and playlist pages — **no sign-in**'**
  String get ytmStep1;

  /// No description provided for @ytmStep2.
  ///
  /// In en, this message translates to:
  /// **'Link import: paste an album or playlist link in the **Library**'**
  String get ytmStep2;

  /// No description provided for @ytmStep3.
  ///
  /// In en, this message translates to:
  /// **'Playback and downloads come straight from **YouTube**'**
  String get ytmStep3;

  /// desktop: settings.storage.offline
  ///
  /// In en, this message translates to:
  /// **'Offline track cache'**
  String get stOfflineCache;

  /// desktop: settings.storage.lyrics
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get stLyrics;

  /// desktop: settings.storage.customization
  ///
  /// In en, this message translates to:
  /// **'Customization'**
  String get stCustom;

  /// No description provided for @stCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get stCounting;

  /// desktop: settings.storage.used
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get stUsed;

  /// desktop: settings.storage.manage
  ///
  /// In en, this message translates to:
  /// **'Clear data'**
  String get stManage;

  /// desktop: settings.storage.items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} item} other{{count} items}}'**
  String stItems(int count);

  /// desktop: settings.storage.of
  ///
  /// In en, this message translates to:
  /// **'{percent}% of {total}'**
  String stUsedOf(String percent, String total);

  /// No description provided for @stClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get stClearAll;

  /// No description provided for @stClearBody.
  ///
  /// In en, this message translates to:
  /// **'The downloaded copies will be deleted and those tracks will stop playing without a network. They stay in your library and playlists.'**
  String get stClearBody;

  /// No description provided for @stClearLyricsBody.
  ///
  /// In en, this message translates to:
  /// **'The saved lyrics will be deleted — they are fetched again on the next playback.'**
  String get stClearLyricsBody;

  /// No description provided for @stClearCustomBody.
  ///
  /// In en, this message translates to:
  /// **'All uploaded images will be deleted. If one is currently set as a background or a cover, it will be reset.'**
  String get stClearCustomBody;

  /// No description provided for @stClearAllBody.
  ///
  /// In en, this message translates to:
  /// **'The caches — offline copies, lyrics and images — will be deleted. Your library and playlists are not affected.'**
  String get stClearAllBody;

  /// No description provided for @stCleared.
  ///
  /// In en, this message translates to:
  /// **'Offline cache cleared, files deleted: {count}'**
  String stCleared(int count);

  /// No description provided for @stCovers.
  ///
  /// In en, this message translates to:
  /// **'Covers'**
  String get stCovers;

  /// No description provided for @stClearCoversBody.
  ///
  /// In en, this message translates to:
  /// **'Downloaded covers will be deleted — they are fetched again the next time they show.'**
  String get stClearCoversBody;

  /// No description provided for @stCoversCleared.
  ///
  /// In en, this message translates to:
  /// **'Cover cache cleared'**
  String get stCoversCleared;

  /// No description provided for @stCoversKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep covers'**
  String get stCoversKeep;

  /// No description provided for @lfmSessionLost.
  ///
  /// In en, this message translates to:
  /// **'The sign-in no longer works — sign in again'**
  String get lfmSessionLost;

  /// No description provided for @stLyricsCleared.
  ///
  /// In en, this message translates to:
  /// **'Lyrics cache cleared'**
  String get stLyricsCleared;

  /// desktop: the switch on the settings.storage.lyrics row
  ///
  /// In en, this message translates to:
  /// **'Keep lyrics'**
  String get stLyricsKeep;

  /// desktop: settings.storage.toast.staleRemoved
  ///
  /// In en, this message translates to:
  /// **'Stale entries removed: {count}'**
  String stStaleRemoved(int count);

  /// desktop: settings.storage.ttl.never
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get stKeepNever;

  /// desktop: settings.storage.ttl.restart
  ///
  /// In en, this message translates to:
  /// **'Until restart'**
  String get stKeepRestart;

  /// desktop: settings.storage.ttl.24h
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get stKeepDay;

  /// desktop: settings.storage.ttl.3d
  ///
  /// In en, this message translates to:
  /// **'3 days'**
  String get stKeep3Days;

  /// desktop: settings.storage.ttl.1w
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get stKeepWeek;

  /// desktop: settings.storage.ttl.1m
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get stKeepMonth;

  /// No description provided for @stCustomCleared.
  ///
  /// In en, this message translates to:
  /// **'Customization library cleared'**
  String get stCustomCleared;

  /// No description provided for @stAllCleared.
  ///
  /// In en, this message translates to:
  /// **'App data cleared'**
  String get stAllCleared;

  /// No description provided for @stBytes.
  ///
  /// In en, this message translates to:
  /// **'{value} B'**
  String stBytes(String value);

  /// No description provided for @stKilobytes.
  ///
  /// In en, this message translates to:
  /// **'{value} KB'**
  String stKilobytes(String value);

  /// No description provided for @stMegabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String stMegabytes(String value);

  /// No description provided for @stGigabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String stGigabytes(String value);

  /// desktop: settings.library.import.title, narrowed: the phone has no watched folders, only single files
  ///
  /// In en, this message translates to:
  /// **'Your own tracks'**
  String get ltImportTitle;

  /// desktop: settings.library.import.desc
  ///
  /// In en, this message translates to:
  /// **'What Bloom does with a file you add with + in All tracks. Tracks already added stay as they are.'**
  String get ltImportDesc;

  /// desktop: settings.library.import.inPlace
  ///
  /// In en, this message translates to:
  /// **'In place'**
  String get ltImportInPlace;

  /// desktop: settings.library.import.inPlaceTip
  ///
  /// In en, this message translates to:
  /// **'The file stays where it is and takes no extra space. Delete or move it and the track stops playing.'**
  String get ltImportInPlaceTip;

  /// desktop: settings.library.import.copy
  ///
  /// In en, this message translates to:
  /// **'Into Bloom'**
  String get ltImportCopy;

  /// desktop: settings.library.import.copyTip
  ///
  /// In en, this message translates to:
  /// **'Bloom copies the file into itself. The track plays even if the original is gone, but the space is used twice.'**
  String get ltImportCopyTip;

  /// No description provided for @ltAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Added {count} track} other{Added {count} tracks}}'**
  String ltAdded(int count);

  /// desktop: lib.import.nothingAdded
  ///
  /// In en, this message translates to:
  /// **'Nothing to add: these tracks are already in the library, or the format is unsupported'**
  String get ltNothingAdded;

  /// phone only: the desktop opens a native dialog from Rust and cannot fail this way
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker'**
  String get ltImportFailed;

  /// phone only: shown in the player when a content:// grant is gone or the copy was wiped
  ///
  /// In en, this message translates to:
  /// **'File is not available'**
  String get ltFileGone;

  /// No description provided for @custLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get custLibrary;

  /// No description provided for @custPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get custPresets;

  /// No description provided for @custLibraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Library is empty — add a photo or GIF'**
  String get custLibraryEmpty;

  /// No description provided for @custAdded.
  ///
  /// In en, this message translates to:
  /// **'Added!'**
  String get custAdded;

  /// No description provided for @custBadUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid image URL'**
  String get custBadUrl;

  /// No description provided for @custFilesAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} file added} other{{count} files added}}'**
  String custFilesAdded(int count);

  /// No description provided for @custCtxBg.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get custCtxBg;

  /// No description provided for @custCtxCover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get custCtxCover;

  /// No description provided for @custCtxSlider.
  ///
  /// In en, this message translates to:
  /// **'Slider'**
  String get custCtxSlider;

  /// No description provided for @custBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get custBlur;

  /// No description provided for @custDim.
  ///
  /// In en, this message translates to:
  /// **'Dim'**
  String get custDim;

  /// No description provided for @custImageGone.
  ///
  /// In en, this message translates to:
  /// **'Image unavailable'**
  String get custImageGone;

  /// No description provided for @custPresetAlsoSave.
  ///
  /// In en, this message translates to:
  /// **'Also save to preset'**
  String get custPresetAlsoSave;

  /// No description provided for @custPresetTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get custPresetTheme;

  /// No description provided for @custPresetTransparency.
  ///
  /// In en, this message translates to:
  /// **'Transparency'**
  String get custPresetTransparency;

  /// No description provided for @custPresetFont.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get custPresetFont;

  /// No description provided for @custAttachPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose from device'**
  String get custAttachPhoto;

  /// No description provided for @custBgUpdated.
  ///
  /// In en, this message translates to:
  /// **'Background updated!'**
  String get custBgUpdated;

  /// No description provided for @custCoverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Cover updated!'**
  String get custCoverUpdated;

  /// No description provided for @custSliderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Slider photo updated!'**
  String get custSliderUpdated;

  /// No description provided for @custBgRemoved.
  ///
  /// In en, this message translates to:
  /// **'Background removed'**
  String get custBgRemoved;

  /// No description provided for @custCoverRemoved.
  ///
  /// In en, this message translates to:
  /// **'Cover reset'**
  String get custCoverRemoved;

  /// No description provided for @custSliderRemoved.
  ///
  /// In en, this message translates to:
  /// **'Slider photo removed'**
  String get custSliderRemoved;

  /// No description provided for @custApplyTo.
  ///
  /// In en, this message translates to:
  /// **'Apply to'**
  String get custApplyTo;

  /// No description provided for @custEffects.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get custEffects;

  /// No description provided for @custCoverMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get custCoverMode;

  /// No description provided for @custCoverModeAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get custCoverModeAlways;

  /// No description provided for @custCoverModeFallback.
  ///
  /// In en, this message translates to:
  /// **'If no cover'**
  String get custCoverModeFallback;

  /// No description provided for @custImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get custImport;

  /// No description provided for @custPresetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Save the current settings as a preset'**
  String get custPresetsEmpty;

  /// No description provided for @custPresetNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name the preset...'**
  String get custPresetNameHint;

  /// No description provided for @custPresetSaved.
  ///
  /// In en, this message translates to:
  /// **'Preset “{name}” saved!'**
  String custPresetSaved(String name);

  /// No description provided for @custPresetNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing is applied — set a background, cover or slider first'**
  String get custPresetNothing;

  /// No description provided for @custPresetsFull.
  ///
  /// In en, this message translates to:
  /// **'No room for more presets — the limit is {limit}'**
  String custPresetsFull(int limit);

  /// No description provided for @custPresetUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get custPresetUntitled;

  /// No description provided for @custPresetApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get custPresetApply;

  /// No description provided for @custPresetExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get custPresetExport;

  /// No description provided for @custPresetApplied.
  ///
  /// In en, this message translates to:
  /// **'Preset “{name}” applied'**
  String custPresetApplied(String name);

  /// No description provided for @custPresetExported.
  ///
  /// In en, this message translates to:
  /// **'Preset saved to file'**
  String get custPresetExported;

  /// No description provided for @custImportBad.
  ///
  /// In en, this message translates to:
  /// **'Could not read file — invalid format'**
  String get custImportBad;

  /// No description provided for @custImported.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} preset imported} other{{count} presets imported}}'**
  String custImported(int count);

  /// No description provided for @apCoverAsBg.
  ///
  /// In en, this message translates to:
  /// **'Track cover as background'**
  String get apCoverAsBg;

  /// No description provided for @apCoverAsBgSub.
  ///
  /// In en, this message translates to:
  /// **'Use the current track cover as the app background'**
  String get apCoverAsBgSub;

  /// desktop: settings.interface.cat.transparency
  ///
  /// In en, this message translates to:
  /// **'TRANSPARENCY'**
  String get apTrGroup;

  /// desktop: settings.interface.transparency.title
  ///
  /// In en, this message translates to:
  /// **'Transparency'**
  String get apTrTitle;

  /// Subtitle of the master switch: the level the blocks are set to
  ///
  /// In en, this message translates to:
  /// **'On ({percent}%)'**
  String apTrOn(int percent);

  /// desktop: settings.interface.transparency.off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get apTrOff;

  /// desktop: settings.interface.transparency.blockOpacity, inverted — here it is how much shows through
  ///
  /// In en, this message translates to:
  /// **'Transparency level'**
  String get apTrLevel;

  /// desktop: settings.interface.transparency.glassStr
  ///
  /// In en, this message translates to:
  /// **'Glass brightness'**
  String get apTrBrightness;

  /// desktop: settings.interface.transparency.glassBlur
  ///
  /// In en, this message translates to:
  /// **'Glass blur'**
  String get apTrBlur;

  /// desktop: settings.interface.transparency.overlays.title
  ///
  /// In en, this message translates to:
  /// **'Overlay transparency'**
  String get apTrOverlays;

  /// desktop: settings.interface.transparency.overlays.sub — no side panels or context menus on the phone
  ///
  /// In en, this message translates to:
  /// **'Glass for sheets, menus and dialogs'**
  String get apTrOverlaysSub;

  /// desktop: welcome.title
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcomeTitle;

  /// desktop: wave.title
  ///
  /// In en, this message translates to:
  /// **'My Wave'**
  String get waveTitle;

  /// desktop: wave.start
  ///
  /// In en, this message translates to:
  /// **'Start My Wave'**
  String get waveStart;

  /// desktop: wave.pick.artist
  ///
  /// In en, this message translates to:
  /// **'In the style of'**
  String get wavePickArtist;

  /// desktop: wave.pick.track
  ///
  /// In en, this message translates to:
  /// **'By track'**
  String get wavePickTrack;

  /// desktop: wave.pick.now
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get wavePickNow;

  /// desktop: wave.back
  ///
  /// In en, this message translates to:
  /// **'Back to the usual'**
  String get waveBack;

  /// desktop: wave.shake
  ///
  /// In en, this message translates to:
  /// **'Shake up My Wave'**
  String get waveShake;

  /// desktop: wave.label.track
  ///
  /// In en, this message translates to:
  /// **'Track wave'**
  String get waveLabelTrack;

  /// desktop: wave.label.queue
  ///
  /// In en, this message translates to:
  /// **'Similar to queue'**
  String get waveLabelQueue;

  /// desktop: wave.label.artist
  ///
  /// In en, this message translates to:
  /// **'Artist wave'**
  String get waveLabelArtist;

  /// track menu item; desktop: wave.startFrom takes the name, here the menu already stands on the track
  ///
  /// In en, this message translates to:
  /// **'Wave from this track'**
  String get waveFromTrack;

  /// artist page action; desktop: wave.label.artist
  ///
  /// In en, this message translates to:
  /// **'Artist wave'**
  String get waveFromArtist;

  /// desktop: wave.dislikes
  ///
  /// In en, this message translates to:
  /// **'Dislikes'**
  String get waveDislikes;

  /// desktop: wave.dislikesTitle
  ///
  /// In en, this message translates to:
  /// **'Wave dislikes'**
  String get waveDislikesTitle;

  /// desktop: wave.noDislikes
  ///
  /// In en, this message translates to:
  /// **'Nothing disliked yet'**
  String get waveNoDislikes;

  /// desktop: wave.dislike
  ///
  /// In en, this message translates to:
  /// **'Dislike'**
  String get waveDislike;

  /// desktop: wave.unlike
  ///
  /// In en, this message translates to:
  /// **'Remove dislike'**
  String get waveUndislike;

  /// desktop: wave.toast.added
  ///
  /// In en, this message translates to:
  /// **'Disliked — won’t suggest it in the wave again'**
  String get waveToastDisliked;

  /// desktop: wave.toast.removed
  ///
  /// In en, this message translates to:
  /// **'Dislike removed'**
  String get waveToastUndisliked;

  /// desktop: wave.toast.stopped
  ///
  /// In en, this message translates to:
  /// **'Wave stopped'**
  String get waveToastStopped;

  /// desktop: wave.toast.notEnough
  ///
  /// In en, this message translates to:
  /// **'Not enough data for My Wave — listen to some music first'**
  String get waveToastNotEnough;

  /// desktop: wave.toast.noSeed
  ///
  /// In en, this message translates to:
  /// **'Couldn’t find a track for the wave'**
  String get waveToastNoSeed;

  /// desktop: wave.toast.queueEmpty
  ///
  /// In en, this message translates to:
  /// **'Queue is empty'**
  String get waveToastQueueEmpty;

  /// desktop: wave.toast.noSeedsInQueue
  ///
  /// In en, this message translates to:
  /// **'No platform tracks in the queue to find similar ones'**
  String get waveToastNoSeedsInQueue;

  /// desktop: wave.toast.artistNoSeeds
  ///
  /// In en, this message translates to:
  /// **'No tracks of this artist to build a wave from'**
  String get waveToastArtistNoSeeds;

  /// desktop: wave.toast.noSimilar
  ///
  /// In en, this message translates to:
  /// **'The platform returned no similar tracks'**
  String get waveToastNoSimilar;

  /// desktop: wave.toast.ymNoAuth
  ///
  /// In en, this message translates to:
  /// **'Not signed in to Yandex Music (Settings → Platforms)'**
  String get waveToastYmNoAuth;

  /// desktop: settings.lastfm.connectedAs, without the ✓ — the page shows it in green
  ///
  /// In en, this message translates to:
  /// **'Connected as {user}'**
  String lfmConnectedAs(String user);

  /// desktop: settings.lastfm.notConnected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get lfmNotConnected;

  /// desktop: settings.lastfm.login
  ///
  /// In en, this message translates to:
  /// **'Sign in with Last.fm'**
  String get lfmLogin;

  /// desktop: settings.lastfm.done
  ///
  /// In en, this message translates to:
  /// **'Done — I confirmed'**
  String get lfmDone;

  /// desktop: settings.lastfm.logout
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get lfmLogout;

  /// phone only: button that opens the key form (on desktop it lives under the “?” popup)
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get lfmKeys;

  /// desktop: settings.lastfm.saveKeys
  ///
  /// In en, this message translates to:
  /// **'Save keys'**
  String get lfmSaveKeys;

  /// desktop: settings.lastfm.scrobble
  ///
  /// In en, this message translates to:
  /// **'Scrobbling'**
  String get lfmScrobble;

  /// desktop: settings.lastfm.scrobble.sub
  ///
  /// In en, this message translates to:
  /// **'Count listened tracks on Last.fm'**
  String get lfmScrobbleSub;

  /// No description provided for @lfmPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} scrobble waits to be sent} other{{count} scrobbles wait to be sent}}'**
  String lfmPending(int count);

  /// desktop: settings.lastfm.nowPlaying.sub
  ///
  /// In en, this message translates to:
  /// **'Update the “Now Playing” status'**
  String get lfmNowPlayingSub;

  /// phone only: the guide sheet, built from the desktop “?” popup
  ///
  /// In en, this message translates to:
  /// **'How to connect Last.fm'**
  String get lfmGuideTitle;

  /// No description provided for @lfmGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your own app key and a browser sign-in'**
  String get lfmGuideSubtitle;

  /// No description provided for @lfmStep1.
  ///
  /// In en, this message translates to:
  /// **'Open **last.fm/api/account/create** and register an app — any name will do.'**
  String get lfmStep1;

  /// No description provided for @lfmStep2.
  ///
  /// In en, this message translates to:
  /// **'Copy **API Key** and **Shared Secret** from there and paste them into the fields below.'**
  String get lfmStep2;

  /// No description provided for @lfmStep3.
  ///
  /// In en, this message translates to:
  /// **'Tap **“Sign in with Last.fm”** — the browser opens, and the password is only entered there.'**
  String get lfmStep3;

  /// No description provided for @lfmStep4.
  ///
  /// In en, this message translates to:
  /// **'Allow access and come back to Bloom: the app checks the sign-in by itself.'**
  String get lfmStep4;

  /// No description provided for @lfmGuideNote.
  ///
  /// In en, this message translates to:
  /// **'The key has to be your own — Bloom has no shared Last.fm key. Your password is never entered into the app.'**
  String get lfmGuideNote;

  /// desktop: lastfm.oauth.gettingToken
  ///
  /// In en, this message translates to:
  /// **'Getting token…'**
  String get lfmGettingToken;

  /// desktop: lastfm.oauth.confirmAccess
  ///
  /// In en, this message translates to:
  /// **'Confirm access on Last.fm, then press “Done”'**
  String get lfmConfirmAccess;

  /// desktop: lastfm.oauth.checking
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get lfmChecking;

  /// desktop: lastfm.oauth.notConfirmed
  ///
  /// In en, this message translates to:
  /// **'Not confirmed — try again'**
  String get lfmNotConfirmed;

  /// desktop: lastfm.oauth.loginFirst
  ///
  /// In en, this message translates to:
  /// **'Press “Sign in with Last.fm” first'**
  String get lfmLoginFirst;

  /// desktop: lastfm.toast.saveApiKeyFirst + lastfm.toast.enterBothKeys, merged into one reason
  ///
  /// In en, this message translates to:
  /// **'Save the API Key and Secret first'**
  String get lfmNeedKeys;

  /// desktop: lastfm.oauth.networkError
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get lfmNetworkError;

  /// desktop: lastfm.oauth.error
  ///
  /// In en, this message translates to:
  /// **'Error: {msg}'**
  String lfmError(String msg);

  /// desktop: lastfm.toast.connectedAs
  ///
  /// In en, this message translates to:
  /// **'Last.fm: connected as {name}'**
  String lfmToastConnected(String name);

  /// desktop: lastfm.toast.disconnected
  ///
  /// In en, this message translates to:
  /// **'Last.fm: disconnected'**
  String get lfmToastDisconnected;

  /// desktop: lastfm.toast.keysSaved
  ///
  /// In en, this message translates to:
  /// **'Last.fm: keys saved'**
  String get lfmToastKeysSaved;

  /// No description provided for @wrMonth.
  ///
  /// In en, this message translates to:
  /// **'Month in review'**
  String get wrMonth;

  /// No description provided for @wrYear.
  ///
  /// In en, this message translates to:
  /// **'Year in review'**
  String get wrYear;

  /// No description provided for @wrNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get wrNext;

  /// desktop: common.close — the button under the last slide
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get wrClose;

  /// desktop: wrapped.watch — the pill on both entry cards
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get wrWatch;

  /// desktop: wrapped.new — badge on an entry nobody opened yet
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get wrNew;

  /// No description provided for @wrIntroMonth.
  ///
  /// In en, this message translates to:
  /// **'Your month in Bloom'**
  String get wrIntroMonth;

  /// No description provided for @wrIntroYear.
  ///
  /// In en, this message translates to:
  /// **'Your year in Bloom'**
  String get wrIntroYear;

  /// No description provided for @wrIntroSub.
  ///
  /// In en, this message translates to:
  /// **'Let’s see how it went'**
  String get wrIntroSub;

  /// No description provided for @wrTimeKicker.
  ///
  /// In en, this message translates to:
  /// **'You listened for'**
  String get wrTimeKicker;

  /// No description provided for @wrTimeSub.
  ///
  /// In en, this message translates to:
  /// **'Plays in this period: {count}'**
  String wrTimeSub(int count);

  /// No description provided for @wrTimeLessThanMin.
  ///
  /// In en, this message translates to:
  /// **'Less than a minute'**
  String get wrTimeLessThanMin;

  /// No description provided for @wrCountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Here’s the whole picture'**
  String get wrCountsTitle;

  /// No description provided for @wrCountsNewTracks.
  ///
  /// In en, this message translates to:
  /// **'Heard for the first time: {count}'**
  String wrCountsNewTracks(int count);

  /// desktop: wrapped.artists.total — the note under the artists list
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} artist in total} other{{count} artists in total}}'**
  String wrArtistsTotalN(int count);

  /// No description provided for @wrSourcesKicker.
  ///
  /// In en, this message translates to:
  /// **'Where it came from'**
  String get wrSourcesKicker;

  /// No description provided for @wrDiscoverKicker.
  ///
  /// In en, this message translates to:
  /// **'New names'**
  String get wrDiscoverKicker;

  /// No description provided for @wrDiscoverTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{You discovered {count} artist} other{You discovered {count} artists}}'**
  String wrDiscoverTitle(int count);

  /// No description provided for @wrHabitsKicker.
  ///
  /// In en, this message translates to:
  /// **'Your habits'**
  String get wrHabitsKicker;

  /// No description provided for @wrHabitsNight.
  ///
  /// In en, this message translates to:
  /// **'You’re a night listener'**
  String get wrHabitsNight;

  /// No description provided for @wrHabitsDay.
  ///
  /// In en, this message translates to:
  /// **'You’re a daytime listener'**
  String get wrHabitsDay;

  /// No description provided for @wrHabitsPeak.
  ///
  /// In en, this message translates to:
  /// **'Favorite hour'**
  String get wrHabitsPeak;

  /// No description provided for @wrHabitsRecord.
  ///
  /// In en, this message translates to:
  /// **'Day record'**
  String get wrHabitsRecord;

  /// No description provided for @wrHabitsStreak.
  ///
  /// In en, this message translates to:
  /// **'Days in a row'**
  String get wrHabitsStreak;

  /// No description provided for @wrHabitsActive.
  ///
  /// In en, this message translates to:
  /// **'Days with music'**
  String get wrHabitsActive;

  /// tracks is an already-formatted wrTracksN string
  ///
  /// In en, this message translates to:
  /// **'{tracks} В· {date}'**
  String wrHabitsRecordValue(Object tracks, Object date);

  /// No description provided for @wrShareKicker.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get wrShareKicker;

  /// No description provided for @wrShareSave.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get wrShareSave;

  /// No description provided for @wrShareFail.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t share the card'**
  String get wrShareFail;

  /// No description provided for @wrCardTime.
  ///
  /// In en, this message translates to:
  /// **'Time with music'**
  String get wrCardTime;

  /// No description provided for @wrCardTopTracks.
  ///
  /// In en, this message translates to:
  /// **'Top tracks'**
  String get wrCardTopTracks;

  /// No description provided for @wrCardTopArtists.
  ///
  /// In en, this message translates to:
  /// **'Top artists'**
  String get wrCardTopArtists;

  /// No description provided for @wrJokeTiny.
  ///
  /// In en, this message translates to:
  /// **'Kind of empty. Did you even press play?'**
  String get wrJokeTiny;

  /// No description provided for @wrJokeSmall.
  ///
  /// In en, this message translates to:
  /// **'Modest. But we counted every single track.'**
  String get wrJokeSmall;

  /// No description provided for @wrJokeOneTrack.
  ///
  /// In en, this message translates to:
  /// **'One track, one artist — respect the consistency.'**
  String get wrJokeOneTrack;

  /// No description provided for @wrPlaysN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} play} other{{count} plays}}'**
  String wrPlaysN(int count);

  /// the noun alone, for tiles where the number is rendered separately
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{play} other{plays}}'**
  String wrPlaysWord(int count);

  /// No description provided for @wrTracksN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} track} other{{count} tracks}}'**
  String wrTracksN(int count);

  /// No description provided for @wrTracksWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{track} other{tracks}}'**
  String wrTracksWord(int count);

  /// No description provided for @wrArtistsWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{artist} other{artists}}'**
  String wrArtistsWord(int count);

  /// No description provided for @wrDaysN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day} other{{count} days}}'**
  String wrDaysN(int count);

  /// No description provided for @wrHoursN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} hour} other{{count} hours}}'**
  String wrHoursN(int count);

  /// the noun alone, for slides where the number is rendered huge and separately
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{hour} other{hours}}'**
  String wrHoursWord(int count);

  /// No description provided for @wrMinutesN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} minute} other{{count} minutes}}'**
  String wrMinutesN(int count);

  /// No description provided for @wrMinutesWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{minute} other{minutes}}'**
  String wrMinutesWord(int count);

  /// desktop: wrapped.n.times — the short form for tight spots: under an artist name the full «plays» eats the line
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} time} other{{count} times}}'**
  String wrTimesN(int count);

  /// No description provided for @wrTimesWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{time} other{times}}'**
  String wrTimesWord(int count);

  /// favorite hour, both sides already formatted as HH:00
  ///
  /// In en, this message translates to:
  /// **'{from} — {to}'**
  String wrHourRange(Object from, Object to);

  /// desktop: settings.system.startup
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get sysStartup;

  /// No description provided for @audRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore the queue'**
  String get audRestoreTitle;

  /// No description provided for @audRestoreSub.
  ///
  /// In en, this message translates to:
  /// **'Bring the track, queue and position back on launch — paused'**
  String get audRestoreSub;

  /// No description provided for @audQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get audQueue;

  /// No description provided for @audAutoSimilarTitle.
  ///
  /// In en, this message translates to:
  /// **'Autoplay similar'**
  String get audAutoSimilarTitle;

  /// No description provided for @audAutoSimilarSub.
  ///
  /// In en, this message translates to:
  /// **'Automatically load similar tracks when there is no next one'**
  String get audAutoSimilarSub;

  /// desktop: settings.system.autoplay.title
  ///
  /// In en, this message translates to:
  /// **'Autoplay'**
  String get audAutoplayTitle;

  /// desktop: settings.system.autoplay.sub
  ///
  /// In en, this message translates to:
  /// **'Restore the last session on launch and keep playing right away'**
  String get audAutoplaySub;

  /// desktop: settings.about.version
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// No description provided for @aboutChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get aboutChecking;

  /// No description provided for @aboutRecheck.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get aboutRecheck;

  /// No description provided for @aboutInstalled.
  ///
  /// In en, this message translates to:
  /// **'Version {v} installed'**
  String aboutInstalled(String v);

  /// desktop: settings.about.uptodate
  ///
  /// In en, this message translates to:
  /// **'You have the latest version'**
  String get aboutUptodate;

  /// desktop: settings.about.available
  ///
  /// In en, this message translates to:
  /// **'Version {v} is available'**
  String aboutAvailable(String v);

  /// desktop: settings.about.error
  ///
  /// In en, this message translates to:
  /// **'Couldn’t check for updates'**
  String get aboutError;

  /// No description provided for @aboutOpenRelease.
  ///
  /// In en, this message translates to:
  /// **'Open the release page'**
  String get aboutOpenRelease;

  /// No description provided for @updInThis.
  ///
  /// In en, this message translates to:
  /// **'In this version'**
  String get updInThis;

  /// desktop: update.whatsNew
  ///
  /// In en, this message translates to:
  /// **'What’s new'**
  String get updWhatsNew;

  /// desktop: update.history
  ///
  /// In en, this message translates to:
  /// **'Update history'**
  String get updHistory;

  /// No description provided for @updHistorySub.
  ///
  /// In en, this message translates to:
  /// **'Notes for previous versions'**
  String get updHistorySub;

  /// desktop: update.historyEmpty
  ///
  /// In en, this message translates to:
  /// **'There are no release notes yet'**
  String get updHistoryEmpty;

  /// desktop: update.notesEmpty
  ///
  /// In en, this message translates to:
  /// **'No notes for this version'**
  String get updNotesEmpty;

  /// No description provided for @updNotesError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load the release notes'**
  String get updNotesError;

  /// desktop: settings.system.importExport
  ///
  /// In en, this message translates to:
  /// **'Import/Export'**
  String get sysImportExport;

  /// desktop: settings.system.exportAll.title
  ///
  /// In en, this message translates to:
  /// **'Export all'**
  String get sysExportTitle;

  /// No description provided for @sysExportSub.
  ///
  /// In en, this message translates to:
  /// **'Save every playlist to a .bloomplaylist file'**
  String get sysExportSub;

  /// desktop: settings.system.export.filename
  ///
  /// In en, this message translates to:
  /// **'bloom-playlists.bloomplaylist'**
  String get sysExportFilename;

  /// No description provided for @sysExported.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get sysExported;

  /// desktop: settings.system.import.title
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get sysImportTitle;

  /// No description provided for @sysImportSub.
  ///
  /// In en, this message translates to:
  /// **'Load playlists from a .bloomplaylist file'**
  String get sysImportSub;

  /// desktop: settings.system.toast.importInvalid
  ///
  /// In en, this message translates to:
  /// **'Error: invalid file'**
  String get sysImportInvalid;

  /// No description provided for @sysImportNoPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists found'**
  String get sysImportNoPlaylists;

  /// desktop: lib.file.oldFormat
  ///
  /// In en, this message translates to:
  /// **'A file from the old Bloom — it can’t be read'**
  String get sysImportOld;

  /// desktop: lib.file.newer
  ///
  /// In en, this message translates to:
  /// **'A file from a newer Bloom — update the app'**
  String get sysImportNewer;

  /// desktop: settings.system.toast.importedFull
  ///
  /// In en, this message translates to:
  /// **'Imported: {pl} pl., {tr} tr.'**
  String sysImportedFull(int pl, int tr);

  /// desktop: settings.system.toast.importedPlaylists
  ///
  /// In en, this message translates to:
  /// **'Playlists imported: {pl}'**
  String sysImportedPlaylists(int pl);

  /// desktop: settings.system.logs
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get sysLogs;

  /// desktop: settings.system.log.title
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get sysLogTitle;

  /// No description provided for @sysLogEmptySub.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get sysLogEmptySub;

  /// No description provided for @sysLogEntries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} entry} other{{count} entries}}'**
  String sysLogEntries(int count);

  /// desktop: logs.copy
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get logsCopy;

  /// No description provided for @logsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get logsSave;

  /// desktop: settings.system.log.clear
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logsClear;

  /// desktop: logs.copied
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get logsCopied;

  /// desktop: settings.system.toast.logsSaved
  ///
  /// In en, this message translates to:
  /// **'Logs saved'**
  String get logsSaved;

  /// desktop: settings.system.toast.logsCleared
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logsCleared;

  /// desktop: logs.empty
  ///
  /// In en, this message translates to:
  /// **'The log is empty'**
  String get logsEmpty;

  /// desktop: settings.system.dangerZone
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get sysDangerZone;

  /// desktop: settings.system.resetSettings.title
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get sysResetTitle;

  /// desktop: settings.system.resetSettings.sub
  ///
  /// In en, this message translates to:
  /// **'Return the look and the options to their defaults'**
  String get sysResetSub;

  /// No description provided for @sysResetBody.
  ///
  /// In en, this message translates to:
  /// **'The look, the player, gestures, transparency and customization presets go back to their defaults. Your library, history, profile and platform logins stay.'**
  String get sysResetBody;

  /// desktop: settings.system.resetSettings.btn
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get sysResetBtn;

  /// No description provided for @sysResetDone.
  ///
  /// In en, this message translates to:
  /// **'Settings reset'**
  String get sysResetDone;

  /// desktop: settings.system.hardReset.title
  ///
  /// In en, this message translates to:
  /// **'Reset everything'**
  String get sysHardResetTitle;

  /// desktop: settings.system.hardReset.sub
  ///
  /// In en, this message translates to:
  /// **'Delete tracks, playlists, history and settings'**
  String get sysHardResetSub;

  /// No description provided for @sysHardResetBody.
  ///
  /// In en, this message translates to:
  /// **'The library, playlists, history, profile, downloads and every setting will be erased for good. There will be nothing to bring them back with.'**
  String get sysHardResetBody;

  /// desktop: settings.system.hardReset.btn
  ///
  /// In en, this message translates to:
  /// **'Reset everything'**
  String get sysHardResetBtn;

  /// No description provided for @sysHardResetDone.
  ///
  /// In en, this message translates to:
  /// **'Everything is erased'**
  String get sysHardResetDone;

  /// desktop: toast.drmSkip
  ///
  /// In en, this message translates to:
  /// **'Track is DRM-protected — skipping'**
  String get playerSkipDrm;

  /// desktop: toast.unavailableSkip
  ///
  /// In en, this message translates to:
  /// **'Track unavailable — skipping'**
  String get playerSkipUnavailable;

  /// desktop: toast.noPlayable
  ///
  /// In en, this message translates to:
  /// **'No tracks available to play'**
  String get playerNoPlayable;

  /// desktop: search.err.drm / sc.err.drm
  ///
  /// In en, this message translates to:
  /// **'Track is DRM-protected'**
  String get errDrm;

  /// desktop: search.err.noStream / sc.err.noStream
  ///
  /// In en, this message translates to:
  /// **'No stream data'**
  String get errNoStream;

  /// desktop: search.err.trackNotFound
  ///
  /// In en, this message translates to:
  /// **'Track not found'**
  String get errTrackNotFound;

  /// desktop: sc.err.unavailable
  ///
  /// In en, this message translates to:
  /// **'SoundCloud is not responding'**
  String get errScUnavailable;

  /// desktop: sc.err.forbidden
  ///
  /// In en, this message translates to:
  /// **'SoundCloud: access denied (401/403)'**
  String get errScForbidden;

  /// desktop: sc.err.clientIdInvalid / sc.err.clientIdExpired
  ///
  /// In en, this message translates to:
  /// **'SoundCloud: client_id is invalid or expired'**
  String get errScClientId;

  /// desktop: ytm.err.noAudio
  ///
  /// In en, this message translates to:
  /// **'YouTube returned no audio stream'**
  String get errYtmNoAudio;

  /// desktop: ytm.err.network
  ///
  /// In en, this message translates to:
  /// **'YouTube is not responding'**
  String get errYtmNetwork;

  /// desktop: settings.interface.cat.font
  ///
  /// In en, this message translates to:
  /// **'FONT'**
  String get apFontCat;

  /// desktop: settings.interface.font.title
  ///
  /// In en, this message translates to:
  /// **'Interface font'**
  String get apFontTitle;

  /// desktop: settings.interface.font.desc
  ///
  /// In en, this message translates to:
  /// **'Choose a font for the whole app'**
  String get apFontDesc;

  /// desktop: settings.interface.font.add
  ///
  /// In en, this message translates to:
  /// **'Upload your own font'**
  String get apFontAdd;

  /// desktop: settings.interface.font.remove
  ///
  /// In en, this message translates to:
  /// **'Remove font'**
  String get apFontRemove;

  /// desktop: settings.interface.font.toast.added
  ///
  /// In en, this message translates to:
  /// **'Fonts added: {n}'**
  String apFontAdded(int n);

  /// desktop: settings.interface.font.toast.badFormat, without .woff/.woff2 — Flutter cannot read them
  ///
  /// In en, this message translates to:
  /// **'Only .ttf and .otf are supported'**
  String get apFontBadFormat;

  /// desktop: settings.interface.font.toast.tooBig
  ///
  /// In en, this message translates to:
  /// **'Font file is larger than {mb} MB'**
  String apFontTooBig(int mb);

  /// desktop: settings.interface.font.toast.readErr
  ///
  /// In en, this message translates to:
  /// **'Could not read the font file'**
  String get apFontReadErr;

  /// phone only: Settings → Integrations row and page title — sync with Bloom on the computer (desktop: Integrations → Phone)
  ///
  /// In en, this message translates to:
  /// **'Computer'**
  String get setPc;

  /// No description provided for @pcNotPaired.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get pcNotPaired;

  /// Connect: the full player's button and sheet title — where the sound goes, this phone or the computer
  ///
  /// In en, this message translates to:
  /// **'Play on'**
  String get pcPlayOn;

  /// No description provided for @pcThisPhone.
  ///
  /// In en, this message translates to:
  /// **'This phone'**
  String get pcThisPhone;

  /// No description provided for @pcPairedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to “{name}”'**
  String pcPairedTo(String name);

  /// when = a time today (12:05) or a date and time
  ///
  /// In en, this message translates to:
  /// **'Synced {when}'**
  String pcSyncedAt(String when);

  /// No description provided for @pcSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get pcSyncing;

  /// No description provided for @pcOffline.
  ///
  /// In en, this message translates to:
  /// **'The computer isn\'t on the network'**
  String get pcOffline;

  /// No description provided for @pcRepair.
  ///
  /// In en, this message translates to:
  /// **'The computer no longer knows this phone — connect again'**
  String get pcRepair;

  /// No description provided for @pcFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync'**
  String get pcFailed;

  /// No description provided for @pcStep1.
  ///
  /// In en, this message translates to:
  /// **'Open **Bloom** on the computer: **Settings → Integrations → Phone** and turn the mode on.'**
  String get pcStep1;

  /// No description provided for @pcStep2.
  ///
  /// In en, this message translates to:
  /// **'Press **Connect a phone** — a QR code and a six-digit code show up.'**
  String get pcStep2;

  /// No description provided for @pcStep3.
  ///
  /// In en, this message translates to:
  /// **'Here press **Scan the QR code** and point the camera at it — or **Type the code**.'**
  String get pcStep3;

  /// No description provided for @pcGuideNote.
  ///
  /// In en, this message translates to:
  /// **'The phone and the computer must be on the same home network. Playlists, likes, follows, dislikes, history and the profile sync; settings stay each device\'s own.'**
  String get pcGuideNote;

  /// No description provided for @pcScan.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code'**
  String get pcScan;

  /// No description provided for @pcEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Type the code'**
  String get pcEnterCode;

  /// No description provided for @pcSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get pcSyncNow;

  /// No description provided for @pcReconnect.
  ///
  /// In en, this message translates to:
  /// **'Connect again'**
  String get pcReconnect;

  /// No description provided for @pcUnpair.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get pcUnpair;

  /// No description provided for @pcUnpairTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect the computer?'**
  String get pcUnpairTitle;

  /// No description provided for @pcUnpairBody.
  ///
  /// In en, this message translates to:
  /// **'Syncing with “{name}” stops. To connect again you\'ll need the computer: Connect a phone on its screen.'**
  String pcUnpairBody(String name);

  /// No description provided for @pcUnpaired.
  ///
  /// In en, this message translates to:
  /// **'Computer forgotten. It lists the phone until you disconnect it there too.'**
  String get pcUnpaired;

  /// No description provided for @pcScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code on the computer\'s screen'**
  String get pcScanHint;

  /// No description provided for @pcNoCamera.
  ///
  /// In en, this message translates to:
  /// **'No access to the camera'**
  String get pcNoCamera;

  /// No description provided for @pcCodeSearching.
  ///
  /// In en, this message translates to:
  /// **'Looking for the computer…'**
  String get pcCodeSearching;

  /// No description provided for @pcCodeNone.
  ///
  /// In en, this message translates to:
  /// **'No computer found. Open “Connect a phone” on it — the phone must be on the same network.'**
  String get pcCodeNone;

  /// No description provided for @pcCodeRetry.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get pcCodeRetry;

  /// No description provided for @pcCodeHint.
  ///
  /// In en, this message translates to:
  /// **'The code from the computer\'s screen'**
  String get pcCodeHint;

  /// No description provided for @pcConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get pcConnect;

  /// No description provided for @pcPaired.
  ///
  /// In en, this message translates to:
  /// **'Connected to “{name}”'**
  String pcPaired(String name);

  /// No description provided for @pcSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get pcSynced;

  /// No description provided for @pcErrNotBloom.
  ///
  /// In en, this message translates to:
  /// **'That\'s not a Bloom code'**
  String get pcErrNotBloom;

  /// No description provided for @pcErrUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The computer doesn\'t answer — is it on the same network?'**
  String get pcErrUnreachable;

  /// No description provided for @pcErrWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong code'**
  String get pcErrWrong;

  /// No description provided for @pcErrClosed.
  ///
  /// In en, this message translates to:
  /// **'“Connect a phone” is closed on the computer'**
  String get pcErrClosed;

  /// No description provided for @pcErrTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many tries — wait for a new code'**
  String get pcErrTooMany;

  /// No description provided for @pcErrFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect'**
  String get pcErrFailed;

  /// No description provided for @taPlayNextHint.
  ///
  /// In en, this message translates to:
  /// **'Plays after the current one'**
  String get taPlayNextHint;

  /// No description provided for @waveFromTrackHint.
  ///
  /// In en, this message translates to:
  /// **'A mix of similar tracks'**
  String get waveFromTrackHint;

  /// No description provided for @waveFromArtistHint.
  ///
  /// In en, this message translates to:
  /// **'A mix based on this artist'**
  String get waveFromArtistHint;

  /// No description provided for @waveDislikeHint.
  ///
  /// In en, this message translates to:
  /// **'Won\'t show up in mixes'**
  String get waveDislikeHint;

  /// No description provided for @waveUndislikeHint.
  ///
  /// In en, this message translates to:
  /// **'Back in the mixes'**
  String get waveUndislikeHint;

  /// No description provided for @tiHint.
  ///
  /// In en, this message translates to:
  /// **'Album, year, length'**
  String get tiHint;

  /// No description provided for @tlOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'A copy inside the app'**
  String get tlOfflineHint;

  /// No description provided for @tlFilesHint.
  ///
  /// In en, this message translates to:
  /// **'To the phone\'s files'**
  String get tlFilesHint;

  /// No description provided for @tlRefreshHint.
  ///
  /// In en, this message translates to:
  /// **'What\'s new in the sources'**
  String get tlRefreshHint;

  /// No description provided for @commonPinHint.
  ///
  /// In en, this message translates to:
  /// **'First in the library'**
  String get commonPinHint;

  /// No description provided for @tlMergeHint.
  ///
  /// In en, this message translates to:
  /// **'Into a new playlist'**
  String get tlMergeHint;

  /// No description provided for @tlConvertHint.
  ///
  /// In en, this message translates to:
  /// **'A copy on another platform'**
  String get tlConvertHint;

  /// No description provided for @tlFindDupsHint.
  ///
  /// In en, this message translates to:
  /// **'Repeats in this list'**
  String get tlFindDupsHint;

  /// No description provided for @tlExportHint.
  ///
  /// In en, this message translates to:
  /// **'To a transfer file'**
  String get tlExportHint;

  /// No description provided for @artistImportHint.
  ///
  /// In en, this message translates to:
  /// **'Into your library'**
  String get artistImportHint;

  /// No description provided for @commonFollowHint.
  ///
  /// In en, this message translates to:
  /// **'The artist joins your library'**
  String get commonFollowHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
