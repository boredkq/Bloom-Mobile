// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get commonBack => 'Назад';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonDone => 'Готово';

  @override
  String get commonApply => 'Применить';

  @override
  String get commonUndo => 'Отменить';

  @override
  String get commonUpload => 'Загрузить';

  @override
  String get commonHide => 'Скрыть';

  @override
  String get commonClear => 'Очистить';

  @override
  String get commonOr => 'или';

  @override
  String get commonPin => 'Закрепить';

  @override
  String get commonUnpin => 'Открепить';

  @override
  String get commonPlay => 'Воспроизвести';

  @override
  String get commonPause => 'Пауза';

  @override
  String get commonShuffle => 'Перемешать';

  @override
  String get commonFollow => 'Подписаться';

  @override
  String get commonUnfollow => 'Отписаться';

  @override
  String get commonLoadMore => 'Загрузить ещё';

  @override
  String get commonTrack => 'Трек';

  @override
  String get commonAlbum => 'Альбом';

  @override
  String get commonPlaylist => 'Плейлист';

  @override
  String get commonArtist => 'Артист';

  @override
  String get commonProfile => 'Профиль';

  @override
  String get commonTracks => 'Треки';

  @override
  String get commonPlaylists => 'Плейлисты';

  @override
  String get commonAlbums => 'Альбомы';

  @override
  String get commonArtists => 'Артисты';

  @override
  String get commonAllTracks => 'Все треки';

  @override
  String get commonFavorites => 'Любимые';

  @override
  String get commonHistory => 'История';

  @override
  String get commonNewPlaylist => 'Новый плейлист';

  @override
  String get commonCreatePlaylist => 'Создать плейлист';

  @override
  String get commonAddToLibrary => 'В библиотеку';

  @override
  String get commonAlreadyInLibrary => 'Уже в библиотеке';

  @override
  String get commonUnknownArtist => 'Неизвестный';

  @override
  String get commonUntitled => 'Без названия';

  @override
  String get commonOfflineBadge => 'офлайн';

  @override
  String get commonAddedOn => 'Добавлен';

  @override
  String get commonCreatedOn => 'Создан';

  @override
  String commonDurHm(int h, int m) {
    return '$hч $mм';
  }

  @override
  String commonDurMin(int m) {
    return '$m мин';
  }

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треков',
      many: '$count треков',
      few: '$count трека',
      one: '$count трек',
    );
    return '$_temp0';
  }

  @override
  String playsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count раз',
      many: '$count раз',
      few: '$count раза',
      one: '$count раз',
    );
    return '$_temp0';
  }

  @override
  String get navHome => 'Главная';

  @override
  String get navLibrary => 'Библиотека';

  @override
  String get navSettings => 'Настройки';

  @override
  String get navSearch => 'Поиск';

  @override
  String get sourceLocal => 'Локальные';

  @override
  String get sourceYandex => 'Яндекс.Музыка';

  @override
  String get homeCharts => 'Чарт';

  @override
  String get homeNewReleases => 'Релизы';

  @override
  String chartUp(int n) {
    return 'Поднялся на $n';
  }

  @override
  String chartDown(int n) {
    return 'Опустился на $n';
  }

  @override
  String get chartSame => 'Без изменений';

  @override
  String get chartNew => 'Новичок чарта';

  @override
  String get chartNewShort => 'нов.';

  @override
  String get relAlbum => 'альбом';

  @override
  String get relSingle => 'сингл';

  @override
  String get relCompilation => 'сборник';

  @override
  String get relPodcast => 'подкаст';

  @override
  String get relEp => 'EP';

  @override
  String get homeForYou => 'Для вас';

  @override
  String get homeForYouAll => 'Вся подборка';

  @override
  String get homeSimilarTo => 'Похожие на';

  @override
  String get playerQueue => 'Очередь';

  @override
  String get queueSecPlayed => 'Прослушано';

  @override
  String get queueSecNow => 'Сейчас играет';

  @override
  String get queueSecNext => 'Далее';

  @override
  String playerNextUp(String title) {
    return 'Далее: $title';
  }

  @override
  String playerSourceSearch(String query) {
    return 'Поиск: $query';
  }

  @override
  String get playerCopied => 'Скопировано';

  @override
  String get playerCopyError => 'Ошибка';

  @override
  String get playerSpeed => 'Скорость';

  @override
  String get playerSpeedCustom => 'Своя скорость';

  @override
  String get playerSpeedReset => 'Сбросить на 1×';

  @override
  String get playerSpeedNightcore => 'Nightcore';

  @override
  String get playerSleep => 'Таймер сна';

  @override
  String playerSleepMinutes(int count) {
    return '$count мин';
  }

  @override
  String playerSleepLeft(String time) {
    return 'Осталось $time';
  }

  @override
  String get playerSleepEndOfTrack => 'До конца трека';

  @override
  String get playerSleepCustom => 'Своё время';

  @override
  String get playerSleepExtend => '+5 минут';

  @override
  String get playerSleepCancel => 'Выключить таймер';

  @override
  String get playerSleepFade => 'Плавное затухание';

  @override
  String get notifChannelName => 'Воспроизведение';

  @override
  String get notifChannelDescription =>
      'Управление музыкой в шторке и на экране блокировки';

  @override
  String get artistSourceNotConnected => 'Площадка этого артиста не подключена';

  @override
  String get artistNotFound => 'Артист не найден';

  @override
  String get artistPopular => 'Популярные';

  @override
  String get artistSimilar => 'Похожие исполнители';

  @override
  String get artistNoTracks => 'У этого артиста нет доступных треков';

  @override
  String get artistAbout => 'Об артисте';

  @override
  String get artistAboutProfile => 'О себе';

  @override
  String get artistLikes => 'Лайки';

  @override
  String get artistShowAll => 'Показать все';

  @override
  String get artistImport => 'Импортировать';

  @override
  String get artistImportLoading => 'Загружаем все треки артиста…';

  @override
  String get artistLikesLoading => 'Загружаем все лайки…';

  @override
  String likesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count лайков',
      many: '$count лайков',
      few: '$count лайка',
      one: '$count лайк',
    );
    return '$_temp0';
  }

  @override
  String get artistNotFoundOnSource => 'Не нашли у площадки';

  @override
  String followedToast(String name) {
    return 'Подписка на $name';
  }

  @override
  String get unfollowedToast => 'Подписка снята';

  @override
  String addedToast(String title, String tracks) {
    return 'Добавлено: $title — $tracks';
  }

  @override
  String get setSourceNotConnected => 'Площадка этого списка не подключена';

  @override
  String get setAlbumNotFound => 'Альбом не найден';

  @override
  String get setPlaylistNotFound => 'Плейлист не найден';

  @override
  String get setNoTracks => 'Нет доступных треков';

  @override
  String get libTabAll => 'Все';

  @override
  String get libTabArtists => 'Исполнители';

  @override
  String get libSystem => 'Системные';

  @override
  String get libAllTracksSub => 'Вся библиотека';

  @override
  String get libLikedSub => 'Лайкнутые треки';

  @override
  String get libNoTracks => 'Нет треков';

  @override
  String get libAutoRefreshTooltip => 'Авто-обновление плейлистов';

  @override
  String get libSortManual => 'По умолчанию';

  @override
  String get libSortNameAsc => 'По имени A–Z';

  @override
  String get libSortNameDesc => 'По имени Z–A';

  @override
  String get tlSortManual => 'По порядку';

  @override
  String get tlSortName => 'По названию';

  @override
  String get tlSortArtist => 'По исполнителю';

  @override
  String get tlSortAlbum => 'По альбому';

  @override
  String get tlSortDuration => 'По длительности';

  @override
  String get tlSortDate => 'По дате добавления';

  @override
  String get tlSortPlays => 'По прослушиваниям';

  @override
  String get tlSortDownloaded => 'Только скачанные';

  @override
  String get tlSortNotDownloaded => 'Только не скачанные';

  @override
  String get tlNothingFound => 'Ничего не нашлось';

  @override
  String get tlNothingDownloaded => 'Скачанных треков тут нет';

  @override
  String get tlNothingNotDownloaded => 'Тут уже всё скачано';

  @override
  String get tlEmptyFav => 'Пока ничего не залайкано';

  @override
  String get histToday => 'Сегодня';

  @override
  String get histYesterday => 'Вчера';

  @override
  String histDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дней назад',
      many: '$count дней назад',
      few: '$count дня назад',
      one: '$count день назад',
    );
    return '$_temp0';
  }

  @override
  String get histWeekAgo => 'Неделю назад';

  @override
  String get tlEmptyAll => 'В библиотеке пока пусто';

  @override
  String get tlEmptyPlaylist => 'В плейлисте пока пусто';

  @override
  String get tlSearchHint => 'В этом списке';

  @override
  String get tlJumpToNow => 'Сейчас играет';

  @override
  String get tlStopSaving => 'Прервать сохранение';

  @override
  String get tlRemoveOffline => 'Убрать из офлайна';

  @override
  String tlListenOffline(int count) {
    return 'Слушать офлайн ($count)';
  }

  @override
  String tlDownloadFiles(int count) {
    return 'Скачать файлами ($count)';
  }

  @override
  String get tlRefreshTracks => 'Обновить треки';

  @override
  String get tlToQueue => 'В очередь';

  @override
  String get tlPlayNext => 'Играть следующими';

  @override
  String tlQueuedTracks(int count) {
    return 'В очередь добавлено: $count';
  }

  @override
  String tlQueuedNext(int count) {
    return 'Играют следующими: $count';
  }

  @override
  String get tlExportPlaylist => 'Экспорт плейлиста';

  @override
  String get tlDeletePlaylist => 'Удалить плейлист';

  @override
  String tlPlaylistDeleted(String name) {
    return '«$name» удалён';
  }

  @override
  String get tlDeletePlaylistWithTracks => 'Удалить плейлист и треки';

  @override
  String get tlPlaylistAndTracksDeleted => 'Удалён с треками';

  @override
  String leAddedToFavorites(String tracks) {
    return 'В любимые: $tracks';
  }

  @override
  String leRemovedFromFavorites(String tracks) {
    return 'Из любимых: $tracks';
  }

  @override
  String leDeleteArm(String tracks) {
    return 'Ещё раз — удалить $tracks';
  }

  @override
  String get leDiscardArm => 'Ещё раз — без сохранения';

  @override
  String cpImported(String title, int count) {
    return 'Импорт: $title — $count';
  }

  @override
  String get cpAllAlreadyIn => 'Всё это уже в библиотеке';

  @override
  String cpAdded(int count) {
    return 'Добавлено: $count';
  }

  @override
  String get cpSourceNoAnswer => 'Площадка не ответила';

  @override
  String get cpNameHint => 'Мой плейлист';

  @override
  String get cpImport => 'Импорт';

  @override
  String get cpLinkHint => 'Вставьте ссылку…';

  @override
  String get cpFromFile => 'Из файла';

  @override
  String cpDestination(String target) {
    return 'Куда: $target';
  }

  @override
  String paEveryMinutes(int count) {
    return '$count мин';
  }

  @override
  String paEveryHours(int count) {
    return '$count ч';
  }

  @override
  String get paJustNow => 'только что';

  @override
  String paMinutesAgo(int count) {
    return '$count мин назад';
  }

  @override
  String paHoursAgo(int count) {
    return '$count ч назад';
  }

  @override
  String paDaysAgo(int count) {
    return '$count дн назад';
  }

  @override
  String get paTitle => 'Авто-обновление';

  @override
  String get paOff => 'Выключено';

  @override
  String get paNoneSelected => 'Ничего не выбрано';

  @override
  String get paOnStartTitle => 'Проверять при запуске';

  @override
  String get paPlaylistsWithSources => 'Плейлисты с источниками';

  @override
  String get paSelectAll => 'Выбрать все';

  @override
  String get paNothingToRefresh =>
      'Обновлять нечего: ни у одного плейлиста нет источников. Привяжите ссылку в правке плейлиста — или импортируйте плейлист по ссылке, он запомнит её сам.';

  @override
  String get paRefreshing => 'Идёт обновление…';

  @override
  String get paSoon => 'вот-вот';

  @override
  String paNextIn(String time) {
    return 'через $time';
  }

  @override
  String paSelected(int selected, int total) {
    return 'Выбрано: $selected из $total';
  }

  @override
  String get paPeriod => 'Периодичность';

  @override
  String get paRunUpdating => 'обновляем…';

  @override
  String get paRunError => 'ошибка';

  @override
  String get paRunNoChanges => 'без изменений';

  @override
  String get paRefreshNow => 'Обновить сейчас';

  @override
  String paBusy(int count) {
    return 'Обновляю $count…';
  }

  @override
  String paProgress(int done, int total) {
    return 'Обновляю: $done/$total';
  }

  @override
  String paNewTracks(int added) {
    return 'Новых треков: $added';
  }

  @override
  String paFailed(int count) {
    return 'Не обновились: $count';
  }

  @override
  String get paNoNewTracks => 'Новых треков нет';

  @override
  String rpBusy(String name) {
    return 'Обновляю «$name»…';
  }

  @override
  String get rpNoAnswer => 'Источник не ответил';

  @override
  String rpNewTracks(int count) {
    return 'Новых треков: $count';
  }

  @override
  String get psTitle => 'Источники обновления';

  @override
  String get psHint =>
      'Привяжите плейлисты, альбомы или лайки с любых площадок — «Обновить треки» добавит из них новые треки наверх плейлиста.';

  @override
  String get psAddHint => 'Вставьте ссылку на плейлист, альбом или профиль…';

  @override
  String get psAdd => 'Привязать';

  @override
  String get psRemove => 'Отвязать';

  @override
  String get psDuplicate => 'Этот источник уже привязан';

  @override
  String get iuUnrecognized => 'Не удалось распознать ссылку';

  @override
  String iuLikesTitle(String name) {
    return 'Лайки · $name';
  }

  @override
  String get iuOnlySupported => 'Только плейлист, альбом, лайки';

  @override
  String get iuNoTracks => 'В этой ссылке нет треков';

  @override
  String get iuPlaylistGone => 'Плейлист больше не существует';

  @override
  String get ofRemoved => 'Убрано из офлайна';

  @override
  String get ofSaving => 'Сохранение офлайн…';

  @override
  String ofAvailable(String name) {
    return 'Доступно офлайн: $name';
  }

  @override
  String get ofNothingToSave => 'Нечего сохранять офлайн';

  @override
  String get ofDownloadingTrack => 'Скачиваю трек…';

  @override
  String ofSaved(String path) {
    return 'Сохранено: $path';
  }

  @override
  String get ofDownloadingFiles => 'Скачиваю файлами…';

  @override
  String get ofNothingToDownload => 'Здесь нечего скачивать';

  @override
  String get ofNoCopies => 'Офлайн-копий не было';

  @override
  String ofRemovedCount(int count) {
    return 'Убрано из офлайна: $count';
  }

  @override
  String get ofAbort => 'Прервать';

  @override
  String get ofNoStorage => 'Нет доступа к хранилищу';

  @override
  String get ofCantSaveTrack => 'Этот трек не сохранить';

  @override
  String get ofBusyWithAnother => 'Уже качаю другой список';

  @override
  String ofDownloadedAll(int count) {
    return 'Скачано треков: $count';
  }

  @override
  String get ofDownloadedNone => 'Ни один трек не скачался';

  @override
  String ofDownloadedPartial(int ok, int total, int failed) {
    return 'Скачано $ok/$total, сбой: $failed';
  }

  @override
  String get ofStreamOnly => 'Только поток, не сохранить';

  @override
  String get ofDrm => 'Трек защищён DRM';

  @override
  String get ofNoFileLink => 'Площадка не дала ссылку';

  @override
  String get ofNoConnection => 'Нет соединения';

  @override
  String ofSaveFailed(String message) {
    return 'Не сохранилось: $message';
  }

  @override
  String get fdPathIos => 'Файлы → На iPhone → Bloom';

  @override
  String get fdPathAndroid => 'Музыка/Bloom';

  @override
  String get fdCantDownload => 'Этот трек нельзя скачать';

  @override
  String get fdNeedPermission => 'Нужен доступ к памяти';

  @override
  String get fdSaveFailed => 'Не удалось сохранить файл';

  @override
  String get fdDownloadFile => 'Скачать файлом';

  @override
  String get fdDownloadCover => 'Скачать обложку';

  @override
  String get fdDownloadingCover => 'Скачиваю обложку…';

  @override
  String get tlConvert => 'Перенести на площадку…';

  @override
  String get cvTitle => 'Перенос на площадку';

  @override
  String cvScanning(String source) {
    return 'Ищем треки на $source…';
  }

  @override
  String get cvScanHint => 'Можно уйти — перенос отменится';

  @override
  String cvSummary(int moved, int kept, int skipped) {
    return 'Перенесено $moved · оставлено $kept · пропущено $skipped';
  }

  @override
  String get cvTakeBest => 'Взять лучшие';

  @override
  String cvCreate(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Создать плейлист из $count треков',
      many: 'Создать плейлист из $count треков',
      few: 'Создать плейлист из $count треков',
      one: 'Создать плейлист из $count трека',
    );
    return '$_temp0';
  }

  @override
  String get cvTagMoved => 'Перенесён';

  @override
  String get cvTagOriginal => 'Оригинал';

  @override
  String get cvTagOnTarget => 'Уже здесь';

  @override
  String get cvTagSkipped => 'Пропущен';

  @override
  String cvNotFound(String source) {
    return 'Не найден на $source';
  }

  @override
  String get cvSearchFailed => 'Площадка не ответила';

  @override
  String get cvKeepOriginal => 'Оставить оригинал';

  @override
  String get cvSkip => 'Пропустить трек';

  @override
  String cvCreated(String name, String tracks) {
    return '«$name» создан — $tracks';
  }

  @override
  String get spSwitch => 'Сменить площадку';

  @override
  String spSearching(String source) {
    return 'Ищем на $source…';
  }

  @override
  String spNow(String source) {
    return 'Теперь играет с $source';
  }

  @override
  String spNotFound(String source) {
    return 'На $source этого трека нет';
  }

  @override
  String get spFailed => 'Площадка не ответила';

  @override
  String get spUnavailable => 'Эта площадка недоступна';

  @override
  String get tlMergeWith => 'Объединить с…';

  @override
  String get mgTitle => 'Объединение плейлистов';

  @override
  String get mgNameHint => 'Название нового плейлиста';

  @override
  String get mgPickHint => 'Выберите, что подмешать';

  @override
  String mgResult(String tracks) {
    return 'Получится $tracks';
  }

  @override
  String mgDupsDropped(int count) {
    return '−$count повторов';
  }

  @override
  String get mgDedup => 'Убрать дубликаты';

  @override
  String get mgDeleteSources => 'Удалить исходные';

  @override
  String get mgNothingToMerge => 'Нет других плейлистов';

  @override
  String mgMerged(String name, String tracks) {
    return '«$name» собран — $tracks';
  }

  @override
  String get tlFindDups => 'Найти дубли';

  @override
  String get dupsTitle => 'Дубликаты треков';

  @override
  String dupsFound(int groups, int extra) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups групп',
      many: '$groups групп',
      few: '$groups группы',
      one: '$groups группа',
    );
    String _temp1 = intl.Intl.pluralLogic(
      extra,
      locale: localeName,
      other: '$extra лишних копий',
      many: '$extra лишних копий',
      few: '$extra лишние копии',
      one: '$extra лишняя копия',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String dupsChecked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Проверено $count треков',
      many: 'Проверено $count треков',
      few: 'Проверено $count трека',
      one: 'Проверен $count трек',
    );
    return '$_temp0';
  }

  @override
  String dupsCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count копий',
      many: '$count копий',
      few: '$count копии',
      one: '$count копия',
    );
    return '$_temp0';
  }

  @override
  String dupsPlays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count прослушиваний',
      many: '$count прослушиваний',
      few: '$count прослушивания',
      one: '$count прослушивание',
    );
    return '$_temp0';
  }

  @override
  String get dupsKeep => 'оставить';

  @override
  String get dupsNone => 'Дубликатов не найдено';

  @override
  String get dupsDelAll => 'Убрать все';

  @override
  String get dupsDelGroup => 'Убрать копии';

  @override
  String dupsRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Убрано $count копий',
      many: 'Убрано $count копий',
      few: 'Убрано $count копии',
      one: 'Убрана $count копия',
    );
    return '$_temp0';
  }

  @override
  String get tiTitle => 'Инфо о треке';

  @override
  String get tiAlbum => 'Альбом';

  @override
  String get tiYear => 'Год';

  @override
  String get tiReleased => 'Дата релиза';

  @override
  String get setRelease => 'Релиз';

  @override
  String get tiDuration => 'Длительность';

  @override
  String get tiPublisher => 'Паблишер';

  @override
  String get tiGenres => 'Жанры';

  @override
  String get tiDescription => 'Описание';

  @override
  String get tiFile => 'Файл';

  @override
  String get tiCredited => 'В титрах';

  @override
  String get tiExplicit => 'Ненормативная лексика';

  @override
  String get tiNothing => 'Больше площадка об этом треке ничего не рассказала';

  @override
  String get taToQueue => 'В очередь';

  @override
  String get taPlayNext => 'Играть следующим';

  @override
  String get taRemoveFromQueue => 'Убрать из очереди';

  @override
  String get taRemoveFromPlaylist => 'Убрать из плейлиста';

  @override
  String get taDownload => 'Скачать';

  @override
  String get taRemoveFromFavorites => 'Убрать из любимых';

  @override
  String get taAddToFavorites => 'В любимые';

  @override
  String get taAddToPlaylist => 'Добавить в плейлист';

  @override
  String get taListenOffline => 'Слушать офлайн';

  @override
  String get taRemoveOffline => 'Убрать из офлайна';

  @override
  String get taGoToArtist => 'Перейти к артисту';

  @override
  String get taDeleteTrack => 'Удалить трек';

  @override
  String get taTrackDeleted => 'Трек удалён';

  @override
  String get taAddedToLibrary => 'Добавлено в библиотеку';

  @override
  String get searchTabAll => 'Все';

  @override
  String get searchHint => 'Поиск';

  @override
  String get searchSourceAll => 'Все источники';

  @override
  String get searchNothingFound => 'Ничего не нашлось';

  @override
  String get searchSectionEmpty => 'В этом разделе ничего не нашлось';

  @override
  String get profileDefaultName => 'Пользователь';

  @override
  String get profileNickCopied => 'Ник скопирован!';

  @override
  String get profileAchievements => 'Достижения';

  @override
  String get profileSaved => 'Профиль сохранён!';

  @override
  String get profileNickname => 'НИКНЕЙМ';

  @override
  String get profileNicknameHint => 'Введи никнейм...';

  @override
  String get profileAbout => 'О СЕБЕ';

  @override
  String get profileAboutHint => 'Расскажи о себе...';

  @override
  String get profileStatus => 'СТАТУС';

  @override
  String get profileStatusHint => '\"Мой статус...\"';

  @override
  String get profileColorSolid => 'Цвет';

  @override
  String get profileColorAuto => 'Авто';

  @override
  String get profileColorGradient => 'Градиент';

  @override
  String get profileAutoHint => 'Цвет обложки самого слушаемого трека';

  @override
  String profileSince(String date) {
    return 'С нами с $date';
  }

  @override
  String profileSumPlays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'прослушиваний',
      many: 'прослушиваний',
      few: 'прослушивания',
      one: 'прослушивание',
    );
    return '$_temp0';
  }

  @override
  String get profileSumTime => 'наслушано';

  @override
  String profileSumStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'дней подряд',
      many: 'дней подряд',
      few: 'дня подряд',
      one: 'день подряд',
    );
    return '$_temp0';
  }

  @override
  String profileSumArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'исполнителей',
      many: 'исполнителей',
      few: 'исполнителя',
      one: 'исполнитель',
    );
    return '$_temp0';
  }

  @override
  String get profileEntryStats => 'Статистика';

  @override
  String profileEntryOf(int total) {
    return 'из $total';
  }

  @override
  String get profileActivityDays => 'за 30 дней';

  @override
  String get historyEmpty => 'Здесь появятся треки, которые ты слушал';

  @override
  String get profileRemoveImage => 'Убрать картинку';

  @override
  String get profileRemovePhoto => 'Убрать фото';

  @override
  String profileZoom(int percent) {
    return 'Масштаб  $percent%';
  }

  @override
  String achUnlockedToast(String name, String tier) {
    return '🏅 $name — $tier';
  }

  @override
  String get achMax => 'Максимум';

  @override
  String achUnlockedAt(String date) {
    return 'получено $date';
  }

  @override
  String get achTierBronze => 'Бронза';

  @override
  String get achTierSilver => 'Серебро';

  @override
  String get achTierGold => 'Золото';

  @override
  String get achListenerName => 'Меломан';

  @override
  String get achListenerDesc => 'Всего прослушиваний';

  @override
  String get achTimeName => 'В наушниках';

  @override
  String get achTimeDesc => 'Время прослушивания';

  @override
  String get achStreakName => 'На волне';

  @override
  String get achStreakDesc => 'Дней подряд с прослушиваниями';

  @override
  String get achMarathonName => 'Марафонец';

  @override
  String get achMarathonDesc => 'Треков за один день';

  @override
  String get achVeteranName => 'Ветеран Bloom';

  @override
  String get achVeteranDesc => 'Время в приложении';

  @override
  String get achDevoteeName => 'Преданность';

  @override
  String get achDevoteeDesc => 'Активных дней всего';

  @override
  String get statsTracks => 'Треков';

  @override
  String get statsPlays => 'Прослушано';

  @override
  String get statsTime => 'Время прослушивания';

  @override
  String get statsUnique => 'Уникальных';

  @override
  String get statsAvgLength => 'Средняя длина';

  @override
  String get statsFavArtist => 'Любимый исполнитель';

  @override
  String get statsAppTime => 'Время в приложении';

  @override
  String get statsRecordDay => 'Рекорд дня';

  @override
  String get statsHoursDay => 'часов/день';

  @override
  String get statsTracksDay => 'треков/день';

  @override
  String get statsArtists => 'артистов';

  @override
  String get statsSources => 'Где слушали чаще';

  @override
  String get statsTopTracks => 'Топ треков';

  @override
  String get statsTopArtists => 'Топ исполнителей';

  @override
  String get statsOverview => 'Обзор';

  @override
  String get statsNoDataYet => 'Пока нет данных';

  @override
  String get statsCopy => 'Скопировать';

  @override
  String get statsClear => 'Очистить';

  @override
  String get statsClearTitle => 'Очистить статистику?';

  @override
  String get statsClearSub =>
      'Прослушивания, история, активность и достижения удалятся';

  @override
  String get statsClearLevel => 'Сбросить и уровень';

  @override
  String levelTitle(int level) {
    return 'Уровень $level';
  }

  @override
  String get levelDesc =>
      'Уровень растёт, пока ты слушаешь музыку и заходишь в Bloom';

  @override
  String levelXp(String into, String span) {
    return '$into / $span XP';
  }

  @override
  String levelToNext(int level, String xp) {
    return 'До $level уровня — ещё $xp XP';
  }

  @override
  String levelTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $count трека',
      many: '≈ $count треков',
      few: '≈ $count трека',
      one: '≈ $count трек',
    );
    return '$_temp0';
  }

  @override
  String get levelHow => 'Как растёт уровень';

  @override
  String get levelPlays => 'Прослушивание треков';

  @override
  String levelPlaysSub(int xp) {
    return '+$xp XP за трек';
  }

  @override
  String get levelDays => 'Ежедневные заходы';

  @override
  String levelDaysSub(int xp) {
    return '+$xp XP в день, больше за дни подряд';
  }

  @override
  String get levelAch => 'Достижения';

  @override
  String levelAchSub(int bronze, int silver, int gold) {
    return '+$bronze / $silver / $gold XP за бронзу, серебро и золото';
  }

  @override
  String get levelBanked => 'Прошлая статистика';

  @override
  String get levelBankedSub => 'Осталось после очистки';

  @override
  String get levelOk => 'Понятно';

  @override
  String get statsCopied => 'Статистика скопирована';

  @override
  String get statsCleared => 'Статистика очищена';

  @override
  String get statsZeroMinutes => '0 мин';

  @override
  String statsHoursMinutes(int hours, int minutes) {
    return '$hoursч $minutesм';
  }

  @override
  String statsMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String get statsShareTitle => '🎵 Моя статистика в Bloom';

  @override
  String statsShareTracks(int count) {
    return '📚 Треков: $count';
  }

  @override
  String statsShareUnique(int count) {
    return '🎵 Уникальных: $count';
  }

  @override
  String statsSharePlays(int count) {
    return '▶️ Прослушано: $count';
  }

  @override
  String statsShareTime(String value) {
    return '🎧 Время прослушивания: $value';
  }

  @override
  String statsShareAvgLength(String value) {
    return '📏 Средняя длина: $value';
  }

  @override
  String statsShareAppTime(String value) {
    return '⏱️ Время в приложении: $value';
  }

  @override
  String statsShareFavArtist(String name) {
    return '⭐ Любимый исполнитель: $name';
  }

  @override
  String statsShareRecordDay(int count) {
    return '🏆 Рекорд дня: $count';
  }

  @override
  String get statsShareAvgPerDay => '📈 В среднем за день:';

  @override
  String get statsShareSources => '📡 Где слушали чаще:';

  @override
  String get statsShareTopTracks => '🔥 Топ треков:';

  @override
  String get statsShareTopArtists => '👤 Топ исполнителей:';

  @override
  String get setGroupApp => 'ПРИЛОЖЕНИЕ';

  @override
  String get setGroupInterface => 'ИНТЕРФЕЙС';

  @override
  String get setGroupIntegrations => 'ИНТЕГРАЦИИ';

  @override
  String get setSystem => 'Система';

  @override
  String get setAudio => 'Аудио';

  @override
  String get setSwipes => 'Свайпы';

  @override
  String get setLanguage => 'Язык';

  @override
  String get setStorage => 'Хранилище';

  @override
  String get setPlayer => 'Плеер';

  @override
  String get setAppearance => 'Внешний вид';

  @override
  String get setMiniPlayer => 'Мини плеер';

  @override
  String get pvGroupTitle => 'Заголовок';

  @override
  String get pvTitleAlignLeft => 'Слева';

  @override
  String get pvTitleAlignCenter => 'По центру';

  @override
  String get pvTitleAlignRight => 'Справа';

  @override
  String get pvStyleRow => 'Стиль плеера';

  @override
  String get pvStyleStandard => 'Стандартный';

  @override
  String get pvStyleVinyl => 'Пластинка';

  @override
  String get pvPlayButtonRow => 'Кнопка воспроизведения';

  @override
  String get pvPlayButtonCircle => 'Круг';

  @override
  String get pvPlayButtonSquare => 'Квадрат';

  @override
  String get pvPlayButtonPlain => 'Без фона';

  @override
  String get pvGroupSlider => 'Слайдер';

  @override
  String get pvSliderStandard => 'Обычный';

  @override
  String get pvSliderThin => 'Тонкий';

  @override
  String get pvSliderWave => 'Волновой';

  @override
  String get pvGroupLyrics => 'Текст песни';

  @override
  String get pvLyricsModeOverlay => 'Поверх обложки';

  @override
  String get pvLyricsModeReplace => 'Вместо обложки';

  @override
  String get pvGroupQueue => 'Очередь';

  @override
  String get pvQueueNormal => 'Обычный';

  @override
  String get pvQueueExtended => 'Расширенный';

  @override
  String get pvNextUp => 'Следующий трек';

  @override
  String get pvNextUpSub => 'Плашка под слайдером с тем, что заиграет дальше';

  @override
  String get pvGroupBg => 'Фон плеера';

  @override
  String get pvBgRow => 'Фон плеера';

  @override
  String get pvBgCover => 'Обложка';

  @override
  String get pvBgCoverSub => 'Обложка трека во весь экран';

  @override
  String get pvBgApp => 'Фон приложения';

  @override
  String get pvBgAppSub => 'Картинка, которая стоит фоном приложения';

  @override
  String get pvBgAppOff => 'Сначала поставьте картинку фоном в «Кастомизации»';

  @override
  String get pvBgColor => 'Цвет';

  @override
  String get pvBgColorSub => 'Адаптивный градиент под обложку';

  @override
  String get pvBgNone => 'Нет';

  @override
  String get pvBgNoneSub => 'Без фона';

  @override
  String get pvBgFxDim => 'Затемнение';

  @override
  String get pvBgFxBlur => 'Размытие';

  @override
  String get pvBgFxOriginal => 'Оригинал';

  @override
  String get pvGroupMiniControls => 'Управление';

  @override
  String get pvMiniBgRow => 'Фон';

  @override
  String get pvMiniBgTheme => 'Стандартный';

  @override
  String get pvMiniBgCoverColor => 'Цвет';

  @override
  String get pvMiniBgCover => 'Обложка';

  @override
  String get pvMiniProgressRow => 'Индикаторы прогресса';

  @override
  String get pvMiniProgressLine => 'Линия';

  @override
  String get pvMiniProgressFill => 'Заливка';

  @override
  String get pvMiniProgressRing => 'Кольцо';

  @override
  String get pvMiniShapeRow => 'Форма обложки';

  @override
  String get pvMiniShapeRounded => 'Закруглённая';

  @override
  String get pvMiniShapeCircle => 'Круг';

  @override
  String get pvMiniRadiusRow => 'Скругление границ';

  @override
  String get pvMiniRadiusNone => 'Нет';

  @override
  String get pvMiniRadiusSoft => 'Мягкое';

  @override
  String get pvMiniRadiusRounded => 'Закруглённое';

  @override
  String get pvMiniRadiusPill => 'Круглое (Pill)';

  @override
  String get pvMiniButtonsRow => 'Кнопки управления';

  @override
  String get pvMiniButtonsSub => 'что стоит в строке справа от названия';

  @override
  String get pvMiniButtonsNone => 'Нет';

  @override
  String get pvMiniButtonPrev => 'Предыдущий';

  @override
  String get pvMiniButtonPlay => 'Плей/Пауза';

  @override
  String get pvMiniButtonNext => 'Следующий';

  @override
  String get pvMiniButtonFav => 'Лайк';

  @override
  String get pvMiniNeighborsRow => 'Соседние треки';

  @override
  String get pvMiniNeighborsOff => 'Скрыты';

  @override
  String get pvMiniNeighborsOn => 'По краям';

  @override
  String get lyricsLoading => 'Загрузка текста…';

  @override
  String get lyricsNotFound => 'Текст не найден';

  @override
  String get swZoneLibrary => 'Библиотека';

  @override
  String get swZoneQueue => 'Очередь';

  @override
  String get swZoneMini => 'Мини-плеер';

  @override
  String get swZonePlayer => 'Плеер';

  @override
  String get swLeft => 'Свайп влево';

  @override
  String get swRight => 'Свайп вправо';

  @override
  String get swActNone => 'Отключено';

  @override
  String get swActLike => 'Лайк';

  @override
  String get swActQueue => 'Добавить в очередь';

  @override
  String get swActPlayNext => 'Следующим';

  @override
  String get swActNext => 'Следующий';

  @override
  String get swActPrev => 'Предыдущий';

  @override
  String get swActDownload => 'Скачать';

  @override
  String get swActDelete => 'Удалить';

  @override
  String get swAddedToQueue => 'Добавлено в очередь';

  @override
  String get swAlreadyInQueue => 'Уже в очереди';

  @override
  String get swPlaysNext => 'Заиграет следующим';

  @override
  String get swLiked => 'Добавлено в любимые';

  @override
  String get swUnliked => 'Убрано из любимых';

  @override
  String get swRemoved => 'Убрано';

  @override
  String get apLanguageRu => 'Русский';

  @override
  String get apLanguageEn => 'English';

  @override
  String get apTheme => 'ТЕМА';

  @override
  String get apThemeRow => 'Тема';

  @override
  String get thNew => 'Своя тема';

  @override
  String get thNameDefault => 'Моя тема';

  @override
  String get thSlotBg => 'Фон';

  @override
  String get thSlotCard => 'Карточка';

  @override
  String get thSlotAccent => 'Акцент';

  @override
  String get thRandom => 'Случайные цвета';

  @override
  String thCreated(String name) {
    return 'Тема «$name» создана';
  }

  @override
  String get thDeleted => 'Пресет удалён';

  @override
  String get thAutoName => 'Авто тема';

  @override
  String get thAutoCard => 'Под обложку трека';

  @override
  String get apAutoAccent => 'Авто акцент';

  @override
  String get apAutoAccentSub => 'Цвет акцента из обложки трека';

  @override
  String get apAutoAccentLevel => 'Яркость акцента';

  @override
  String get apBgGroup => 'ФОН';

  @override
  String get apBadgesTitle => 'Бейджи в цвете акцента';

  @override
  String get apBadgesSubtitle =>
      'По умолчанию бейджи источников в своих фирменных цветах; включи — красить в акцент';

  @override
  String get apNavBar => 'ТАБ-БАР';

  @override
  String get apNavBarRow => 'Таб-бар';

  @override
  String get apNavBarPlain => 'Обычный';

  @override
  String get apNavBarRounded => 'Скруглённый';

  @override
  String get apNavBarDome => 'Купол';

  @override
  String get apNavBarFloating => 'Плавающий';

  @override
  String get apNavBarPill => 'Пилюля';

  @override
  String get apNavTabsRow => 'Порядок вкладок';

  @override
  String get apNavTabsDrag =>
      'Потяните вкладку за ручку, чтобы поменять её место в баре';

  @override
  String get apNavMarkRow => 'Выделение активного';

  @override
  String get apNavMarkNone => 'Нет';

  @override
  String get apNavMarkPill => 'Подложка';

  @override
  String get apNavMarkDot => 'Точка';

  @override
  String get apNavMarkLine => 'Линия';

  @override
  String get apNavLabelsRow => 'Подписи';

  @override
  String get apNavLabelsNone => 'Нет';

  @override
  String get apNavLabelsAlways => 'Всегда';

  @override
  String get apNavLabelsActive => 'У активного';

  @override
  String get apNavHomeLogoRow => 'Логотип вместо «Главной»';

  @override
  String get apNavHomeLogoSub => 'Знак Bloom на месте иконки таба «Главная»';

  @override
  String get scHelp =>
      'Обычно не нужен: ключ подбирается сам — скрейпом сайта, а если не вышло, перебором известных. Своё значение имеет смысл вбить, если SoundCloud перестал отвечать.';

  @override
  String get scHint => 'Автоматически';

  @override
  String get scCheckConnection => 'Проверить соединение';

  @override
  String get scConnectionOk => 'Соединение работает';

  @override
  String get scConnectionFail => 'Не отвечает';

  @override
  String get scActiveKey => 'Активный ключ';

  @override
  String get scSetup => 'Настроить';

  @override
  String get scReconfigure => 'Перенастроить';

  @override
  String get scStatusAuto => 'Ключ подбирается автоматически';

  @override
  String get scStatusManual => 'Работает со своим client_id';

  @override
  String get scGuideTitle => 'Как получить client_id';

  @override
  String get scGuideSubtitle => 'Пошаговая инструкция — обычно она не нужна';

  @override
  String get scStep1 => 'Открой **soundcloud.com** в браузере на компьютере';

  @override
  String get scStep2 => 'Нажми **F12** → вкладка **Network**';

  @override
  String get scStep3 => 'Нажми play на любом треке';

  @override
  String get scStep4 => 'Найди запрос к **api-v2.soundcloud.com**';

  @override
  String get scStep5 => 'Скопируй параметр **client_id** из URL';

  @override
  String get ymChecking => 'Проверяю…';

  @override
  String get ymConnected => '✓ Подключено';

  @override
  String get ymNotConnected => 'Не подключено';

  @override
  String get ymLogout => 'Выйти';

  @override
  String get ymPlusActiveA => 'Яндекс Плюс активен';

  @override
  String get ymPlusActiveB => '— треки играют напрямую из Яндекса.';

  @override
  String get ymPlusNoneA => 'Без Плюса';

  @override
  String get ymPlusNoneB =>
      '— некоторые треки могут быть недоступны для воспроизведения.';

  @override
  String get ymPlusUnknown => 'Статус подписки неизвестен.';

  @override
  String get ymConnect => 'Подключить Яндекс.Музыку';

  @override
  String get ymCodePromptA => 'Открой';

  @override
  String get ymCodePromptB => 'и введи код:';

  @override
  String get ymOpenPage => 'Открыть страницу';

  @override
  String get ymCodeCopied => 'Код скопирован';

  @override
  String get ymGettingCode => 'Получаю код…';

  @override
  String get ymWaiting => 'Ожидаю подтверждения…';

  @override
  String get ymCodeExpired => 'Код истёк — нажми «Подключить» заново.';

  @override
  String get ymErrAuth => 'Войдите в Яндекс заново';

  @override
  String get ymErrNeedPlus => 'Нужна подписка Яндекс Плюс';

  @override
  String get ymErrNetwork => 'Яндекс не отвечает';

  @override
  String get ymGuideTitle => 'Как подключить Яндекс.Музыку';

  @override
  String get ymGuideSubtitle => 'Вход через Яндекс ID — четыре шага';

  @override
  String get ymStep1 => 'Нажми **Подключить Яндекс.Музыку**';

  @override
  String get ymStep2 =>
      'Откроется страница **ya.ru/device** — войди в свой аккаунт';

  @override
  String get ymStep3 =>
      'Введи там код, который покажет Bloom (тап по коду копирует его)';

  @override
  String get ymStep4 => 'Вернись в приложение — подключение подхватится само';

  @override
  String get ymGuideNote =>
      'Без подписки Яндекс Плюс часть треков не проигрывается — их можно слушать с других площадок.';

  @override
  String get ytmConfigured => 'Настроен';

  @override
  String get ytmNoAuth => 'Пока что, авторизация не нужна';

  @override
  String get ytmHelp =>
      'Поиск, страницы и импорт по ссылке работают без авторизации. Воспроизведение и скачивание идут напрямую с YouTube.';

  @override
  String get ytmGuideTitle => 'Что уже работает';

  @override
  String get ytmGuideSubtitle => 'Подключать ничего не нужно';

  @override
  String get ytmStep1 =>
      'Поиск, страницы артистов, альбомов и плейлистов — **без входа**';

  @override
  String get ytmStep2 =>
      'Импорт по ссылке: вставь ссылку на альбом или плейлист в **Библиотеке**';

  @override
  String get ytmStep3 =>
      'Воспроизведение и скачивание идут напрямую с **YouTube**';

  @override
  String get stOfflineCache => 'Офлайн-кеш треков';

  @override
  String get stLyrics => 'Тексты';

  @override
  String get stCustom => 'Кастомизация';

  @override
  String get stUsed => 'Занято';

  @override
  String get stManage => 'Очистка данных';

  @override
  String stCleared(int count) {
    return 'Офлайн-кеш очищен: $count';
  }

  @override
  String get stCovers => 'Обложки';

  @override
  String get stCoversCleared => 'Кеш обложек очищен';

  @override
  String get stCoversKeep => 'Хранить обложки';

  @override
  String get lfmSessionLost => 'Вход больше не действует — войди заново';

  @override
  String get stLyricsCleared => 'Кеш текстов очищен';

  @override
  String get stLyricsKeep => 'Хранить тексты';

  @override
  String get stLyricsKeepFor => 'Срок текстов';

  @override
  String stClearSize(String size) {
    return 'Очистить $size';
  }

  @override
  String get stClearSure => 'Точно очистить?';

  @override
  String stStaleRemoved(int count) {
    return 'Удалено устаревших: $count';
  }

  @override
  String get stKeepNever => 'Без срока';

  @override
  String get stKeepRestart => 'До перезапуска';

  @override
  String get stKeepDay => '24 часа';

  @override
  String get stKeep3Days => '3 дня';

  @override
  String get stKeepWeek => '1 неделя';

  @override
  String get stKeepMonth => '1 месяц';

  @override
  String get stCustomCleared => 'Библиотека очищена';

  @override
  String get stAllCleared => 'Данные очищены';

  @override
  String stKilobytes(String value) {
    return '$value КБ';
  }

  @override
  String stMegabytes(String value) {
    return '$value МБ';
  }

  @override
  String stGigabytes(String value) {
    return '$value ГБ';
  }

  @override
  String get ltImportTitle => 'Свои треки';

  @override
  String get ltImportDesc =>
      'Что Bloom делает с файлом, добавленным плюсом во «Всех треках». Уже добавленные треки не меняются.';

  @override
  String get ltImportInPlace => 'На месте';

  @override
  String get ltImportInPlaceTip =>
      'Файл остаётся там, где лежит, и места не занимает. Удалите или перенесёте его — трек перестанет играть.';

  @override
  String get ltImportCopy => 'В Bloom';

  @override
  String get ltImportCopyTip =>
      'Bloom копирует файл к себе. Трек играет, даже если оригинала больше нет, но место занято дважды.';

  @override
  String ltAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавлено $count треков',
      many: 'Добавлено $count треков',
      few: 'Добавлено $count трека',
      one: 'Добавлен $count трек',
    );
    return '$_temp0';
  }

  @override
  String get ltNothingAdded => 'Нечего добавить';

  @override
  String get ltImportFailed => 'Не открылся выбор файлов';

  @override
  String get ltFileGone => 'Файл недоступен';

  @override
  String get custLibrary => 'Библиотека';

  @override
  String get custPresets => 'Пресеты';

  @override
  String get custLibraryEmpty => 'Библиотека пуста — добавьте фото или GIF';

  @override
  String get custAdded => 'Добавлено!';

  @override
  String get custBadUrl => 'Неверная ссылка на картинку';

  @override
  String custFilesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавлено $count файлов',
      many: 'Добавлено $count файлов',
      few: 'Добавлено $count файла',
      one: 'Добавлен $count файл',
    );
    return '$_temp0';
  }

  @override
  String get custCtxBg => 'Фон';

  @override
  String get custCtxCover => 'Обложка';

  @override
  String get custCtxSlider => 'Слайдер';

  @override
  String get custBlur => 'Размытие';

  @override
  String get custDim => 'Затемнение';

  @override
  String get custImageGone => 'Картинка недоступна';

  @override
  String get custPresetAlsoSave => 'Добавить в пресет';

  @override
  String get custPresetTheme => 'Тема';

  @override
  String get custPresetTransparency => 'Прозрачность';

  @override
  String get custPresetFont => 'Шрифт';

  @override
  String get custAttachPhoto => 'Выбрать с устройства';

  @override
  String get custBgUpdated => 'Фон обновлён!';

  @override
  String get custCoverUpdated => 'Обложка обновлена!';

  @override
  String get custSliderUpdated => 'Фото слайдера обновлено!';

  @override
  String get custBgRemoved => 'Фон удалён';

  @override
  String get custCoverRemoved => 'Обложка сброшена';

  @override
  String get custSliderRemoved => 'Фото слайдера удалено';

  @override
  String get custApplyTo => 'Применить к';

  @override
  String get custEffects => 'Эффекты';

  @override
  String get custCoverMode => 'Режим';

  @override
  String get custCoverModeAlways => 'Всегда';

  @override
  String get custCoverModeFallback => 'Если нет обложки';

  @override
  String get custImport => 'Импорт';

  @override
  String get custPresetsEmpty => 'Сохраните текущие настройки как пресет';

  @override
  String get custPresetNameHint => 'Назовите пресет…';

  @override
  String custPresetSaved(String name) {
    return 'Пресет «$name» сохранён!';
  }

  @override
  String get custPresetNothing => 'Нечего сохранять';

  @override
  String custPresetsFull(int limit) {
    return 'Больше $limit не поместится';
  }

  @override
  String get custPresetUntitled => 'Без названия';

  @override
  String get custPresetApply => 'Применить';

  @override
  String get custPresetExport => 'Экспортировать';

  @override
  String custPresetApplied(String name) {
    return 'Пресет «$name» применён';
  }

  @override
  String get custPresetExported => 'Пресет сохранён в файл';

  @override
  String get custImportBad => 'Неверный формат файла';

  @override
  String custImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Импортировано $count пресетов',
      many: 'Импортировано $count пресетов',
      few: 'Импортировано $count пресета',
      one: 'Импортирован $count пресет',
    );
    return '$_temp0';
  }

  @override
  String get apCoverAsBg => 'Обложка трека как фон';

  @override
  String get apCoverAsBgSub =>
      'Использовать обложку текущего трека как фон приложения';

  @override
  String get apTrGroup => 'ПРОЗРАЧНОСТЬ';

  @override
  String get apTrTitle => 'Прозрачность';

  @override
  String apTrOn(int percent) {
    return 'Включено ($percent%)';
  }

  @override
  String get apTrOff => 'Выключено';

  @override
  String get apTrLevel => 'Уровень прозрачности';

  @override
  String get apTrBrightness => 'Яркость стекла';

  @override
  String get apTrBlur => 'Размытие стекла';

  @override
  String get apTrOverlays => 'Прозрачность оверлеев';

  @override
  String get apTrOverlaysSub => 'Стекло для шторок, меню и диалогов';

  @override
  String get welcomeTitle => 'Добро пожаловать';

  @override
  String get waveTitle => 'Моя волна';

  @override
  String get waveStart => 'Запустить «Мою волну»';

  @override
  String get wavePickArtist => 'В стиле артиста';

  @override
  String get wavePickTrack => 'По треку';

  @override
  String get wavePickNow => 'Сейчас играет';

  @override
  String get waveBack => 'Назад к привычному';

  @override
  String get waveShake => 'Встряхнуть Мою волну';

  @override
  String get waveLabelTrack => 'Волна по треку';

  @override
  String get waveLabelQueue => 'Похожие на очередь';

  @override
  String get waveLabelArtist => 'Волна по артисту';

  @override
  String get waveFromTrack => 'Волна по этому треку';

  @override
  String get waveFromArtist => 'Волна по артисту';

  @override
  String get waveDislikes => 'Дизлайки';

  @override
  String get waveDislikesTitle => 'Дизлайки в волне';

  @override
  String get waveNoDislikes => 'Дизлайков пока нет';

  @override
  String get waveDislike => 'Дизлайк';

  @override
  String get waveUndislike => 'Снять дизлайк';

  @override
  String get waveToastDisliked => 'Больше не предложу в волне';

  @override
  String get waveToastUndisliked => 'Дизлайк снят';

  @override
  String get waveToastStopped => 'Волна остановлена';

  @override
  String get waveToastNotEnough => 'Мало данных: послушай музыку';

  @override
  String get waveToastNoSeed => 'Не нашёл трек для волны';

  @override
  String get waveToastQueueEmpty => 'Очередь пуста';

  @override
  String get waveToastNoSeedsInQueue => 'В очереди нет треков площадок';

  @override
  String get waveToastArtistNoSeeds => 'Нет треков артиста для волны';

  @override
  String get waveToastNoSimilar => 'Похожих треков нет';

  @override
  String get waveToastYmNoAuth => 'Войдите в Яндекс.Музыку';

  @override
  String lfmConnectedAs(String user) {
    return 'Подключено как $user';
  }

  @override
  String get lfmNotConnected => 'Не подключено';

  @override
  String get lfmLogin => 'Войти через Last.fm';

  @override
  String get lfmDone => 'Готово — я подтвердил';

  @override
  String get lfmLogout => 'Выйти';

  @override
  String get lfmKeys => 'Ключи API';

  @override
  String get lfmSaveKeys => 'Сохранить ключи';

  @override
  String get lfmScrobble => 'Скробблинг';

  @override
  String get lfmScrobbleSub => 'Засчитывать прослушанные треки на Last.fm';

  @override
  String lfmPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count скробблов ждут отправки',
      few: '$count скроббла ждут отправки',
      one: '$count скроббл ждёт отправки',
    );
    return '$_temp0';
  }

  @override
  String get lfmNowPlayingSub => 'Обновлять статус «Сейчас играет»';

  @override
  String get lfmGuideTitle => 'Как подключить Last.fm';

  @override
  String get lfmGuideSubtitle => 'Свой ключ приложения и вход через браузер';

  @override
  String get lfmStep1 =>
      'Открой **last.fm/api/account/create** и заведи приложение — имя любое.';

  @override
  String get lfmStep2 =>
      'Скопируй оттуда **API Key** и **Shared Secret** и вставь их в поля ниже.';

  @override
  String get lfmStep3 =>
      'Нажми **«Войти через Last.fm»** — откроется браузер, пароль вводится только там.';

  @override
  String get lfmStep4 =>
      'Разреши доступ и вернись в Bloom: приложение проверит вход само.';

  @override
  String get lfmGuideNote =>
      'Ключ нужен свой — общего ключа Last.fm у Bloom нет. Пароль в приложение не вводится.';

  @override
  String get lfmGettingToken => 'Получаю токен…';

  @override
  String get lfmConfirmAccess =>
      'Подтверди доступ на Last.fm, затем нажми «Готово»';

  @override
  String get lfmChecking => 'Проверяю…';

  @override
  String get lfmNotConfirmed => 'Не подтверждено — попробуй ещё раз';

  @override
  String get lfmLoginFirst => 'Сначала нажми «Войти через Last.fm»';

  @override
  String get lfmNeedKeys => 'Сначала сохрани API Key и Secret';

  @override
  String get lfmNetworkError => 'Сетевая ошибка';

  @override
  String lfmError(String msg) {
    return 'Ошибка: $msg';
  }

  @override
  String lfmToastConnected(String name) {
    return 'Last.fm: подключено как $name';
  }

  @override
  String get lfmToastDisconnected => 'Last.fm: отключено';

  @override
  String get lfmToastKeysSaved => 'Last.fm: ключи сохранены';

  @override
  String get wrMonth => 'Итоги месяца';

  @override
  String get wrYear => 'Итоги года';

  @override
  String get wrNext => 'Далее';

  @override
  String get wrClose => 'Закрыть';

  @override
  String get wrWatch => 'Смотреть';

  @override
  String get wrNew => 'Новое';

  @override
  String get wrIntroMonth => 'Твой месяц в Bloom';

  @override
  String get wrIntroYear => 'Твой год в Bloom';

  @override
  String get wrIntroSub => 'Посмотрим, что это было';

  @override
  String get wrTimeKicker => 'Ты слушал музыку';

  @override
  String wrTimeSub(int count) {
    return 'Прослушиваний за период: $count';
  }

  @override
  String get wrTimeLessThanMin => 'Меньше минуты';

  @override
  String get wrCountsTitle => 'Вот сколько всего было';

  @override
  String wrCountsNewTracks(int count) {
    return 'Впервые услышано: $count';
  }

  @override
  String wrArtistsTotalN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count артистов всего',
      many: '$count артистов всего',
      few: '$count артиста всего',
      one: '$count артист всего',
    );
    return '$_temp0';
  }

  @override
  String get wrSourcesKicker => 'Откуда музыка';

  @override
  String get wrDiscoverKicker => 'Новые имена';

  @override
  String wrDiscoverTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ты открыл $count артистов',
      many: 'Ты открыл $count артистов',
      few: 'Ты открыл $count артистов',
      one: 'Ты открыл $count артиста',
    );
    return '$_temp0';
  }

  @override
  String get wrHabitsKicker => 'Твои привычки';

  @override
  String get wrHabitsNight => 'Ты ночной слушатель';

  @override
  String get wrHabitsDay => 'Ты дневной слушатель';

  @override
  String get wrHabitsPeak => 'Любимый час';

  @override
  String get wrHabitsRecord => 'Рекорд дня';

  @override
  String get wrHabitsStreak => 'Дней подряд';

  @override
  String get wrHabitsActive => 'Дней с музыкой';

  @override
  String wrHabitsRecordValue(Object tracks, Object date) {
    return '$tracks · $date';
  }

  @override
  String get wrShareKicker => 'Забирай на память';

  @override
  String get wrShareSave => 'Поделиться';

  @override
  String get wrShareFail => 'Не отправилась карточка';

  @override
  String get wrCardTime => 'Времени с музыкой';

  @override
  String get wrCardTopTracks => 'Топ-треки';

  @override
  String get wrCardTopArtists => 'Топ-артисты';

  @override
  String get wrJokeTiny => 'Как-то пусто. Ты вообще включал музыку?';

  @override
  String get wrJokeSmall => 'Скромно. Но мы посчитали каждый трек.';

  @override
  String get wrJokeOneTrack => 'Один трек, один артист — уважаем постоянство.';

  @override
  String wrPlaysWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'прослушиваний',
      many: 'прослушиваний',
      few: 'прослушивания',
      one: 'прослушивание',
    );
    return '$_temp0';
  }

  @override
  String wrTracksN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треков',
      many: '$count треков',
      few: '$count трека',
      one: '$count трек',
    );
    return '$_temp0';
  }

  @override
  String wrTracksWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'треков',
      many: 'треков',
      few: 'трека',
      one: 'трек',
    );
    return '$_temp0';
  }

  @override
  String wrArtistsWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'артистов',
      many: 'артистов',
      few: 'артиста',
      one: 'артист',
    );
    return '$_temp0';
  }

  @override
  String wrDaysN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дней',
      many: '$count дней',
      few: '$count дня',
      one: '$count день',
    );
    return '$_temp0';
  }

  @override
  String wrHoursN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count часов',
      many: '$count часов',
      few: '$count часа',
      one: '$count час',
    );
    return '$_temp0';
  }

  @override
  String wrHoursWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'часов',
      many: 'часов',
      few: 'часа',
      one: 'час',
    );
    return '$_temp0';
  }

  @override
  String wrMinutesN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count минут',
      many: '$count минут',
      few: '$count минуты',
      one: '$count минута',
    );
    return '$_temp0';
  }

  @override
  String wrMinutesWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'минут',
      many: 'минут',
      few: 'минуты',
      one: 'минута',
    );
    return '$_temp0';
  }

  @override
  String wrTimesN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count раз',
      many: '$count раз',
      few: '$count раза',
      one: '$count раз',
    );
    return '$_temp0';
  }

  @override
  String wrTimesWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'раз',
      many: 'раз',
      few: 'раза',
      one: 'раз',
    );
    return '$_temp0';
  }

  @override
  String wrHourRange(Object from, Object to) {
    return '$from — $to';
  }

  @override
  String get sysStartup => 'Запуск';

  @override
  String get audRestoreTitle => 'Восстановление очереди';

  @override
  String get audRestoreSub =>
      'Возвращать при запуске трек, очередь и позицию — на паузе';

  @override
  String get audQueue => 'Очередь';

  @override
  String get audAutoSimilarTitle => 'Авто похожие';

  @override
  String get audAutoSimilarSub =>
      'Автоматически догружать похожие треки, когда следующего нет';

  @override
  String get audAutoplayTitle => 'Автовоспроизведение';

  @override
  String get audAutoplaySub =>
      'Восстановить прошлую сессию при запуске и сразу продолжить';

  @override
  String get aboutVersion => 'Версия';

  @override
  String get aboutChecking => 'Проверяем обновления…';

  @override
  String get aboutRecheck => 'Проверить снова';

  @override
  String aboutInstalled(String v) {
    return 'Установлена версия $v';
  }

  @override
  String get aboutUptodate => 'Установлена последняя версия';

  @override
  String aboutAvailable(String v) {
    return 'Доступна версия $v';
  }

  @override
  String get aboutError => 'Не удалось проверить обновления';

  @override
  String get aboutOpenRelease => 'Открыть страницу релиза';

  @override
  String get updInThis => 'В этой версии';

  @override
  String get updWhatsNew => 'Что нового';

  @override
  String get updHistory => 'История обновлений';

  @override
  String get updHistorySub => 'Заметки к прошлым версиям';

  @override
  String get updHistoryEmpty => 'Заметок к версиям пока нет';

  @override
  String get updNotesEmpty => 'К этой версии заметок нет';

  @override
  String get updNotesError => 'Не удалось загрузить заметки';

  @override
  String get sysImportExport => 'Импорт/Экспорт';

  @override
  String get sysExportTitle => 'Экспортировать все';

  @override
  String get sysExportSub => 'Сохранить все плейлисты в файл .bloomplaylist';

  @override
  String get sysExportFilename => 'bloom-плейлисты.bloomplaylist';

  @override
  String get sysExported => 'Файл сохранён';

  @override
  String get sysImportTitle => 'Импортировать';

  @override
  String get sysImportSub => 'Загрузить плейлисты из файла .bloomplaylist';

  @override
  String get sysImportInvalid => 'Ошибка: невалидный файл';

  @override
  String get sysImportNoPlaylists => 'Плейлисты не найдены';

  @override
  String get sysImportOld => 'Формат не поддерживается';

  @override
  String get sysImportNewer => 'Файл новее: обновите Bloom';

  @override
  String sysImportedFull(int pl, int tr) {
    return 'Импорт: $pl пл., $tr тр.';
  }

  @override
  String sysImportedPlaylists(int pl) {
    return 'Импорт плейлистов: $pl';
  }

  @override
  String get sysLogs => 'Логи';

  @override
  String get sysLogTitle => 'Журнал работы';

  @override
  String get sysLogEmptySub => 'Пока пусто';

  @override
  String sysLogEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '$count запись',
    );
    return '$_temp0';
  }

  @override
  String get logsCopy => 'Копировать';

  @override
  String get logsSave => 'Сохранить';

  @override
  String get logsClear => 'Очистить';

  @override
  String get logsCopied => 'Скопировано';

  @override
  String get logsSaved => 'Логи сохранены';

  @override
  String get logsCleared => 'Логи очищены';

  @override
  String get logsEmpty => 'Журнал пуст';

  @override
  String get sysDangerZone => 'Опасная зона';

  @override
  String get sysResetTitle => 'Сбросить настройки';

  @override
  String get sysResetSub =>
      'Вернуть оформление и параметры к значениям по умолчанию';

  @override
  String get sysResetBody =>
      'Оформление, плеер, жесты, прозрачность и пресеты кастомизации вернутся к умолчаниям. Библиотека, история, профиль и входы в площадки останутся.';

  @override
  String get sysResetBtn => 'Сбросить';

  @override
  String get sysResetDone => 'Настройки сброшены';

  @override
  String get sysHardResetTitle => 'Сбросить всё';

  @override
  String get sysHardResetSub => 'Удалить треки, плейлисты, историю и настройки';

  @override
  String get sysHardResetBody =>
      'Библиотека, плейлисты, история, профиль, скачанное и все настройки будут стёрты безвозвратно. Вернуть их будет нечем.';

  @override
  String get sysHardResetBtn => 'Сбросить всё';

  @override
  String get sysHardResetDone => 'Всё стёрто';

  @override
  String get playerSkipDrm => 'Трек защищён DRM — пропускаем';

  @override
  String get playerSkipUnavailable => 'Трек недоступен — пропускаем';

  @override
  String get playerNoPlayable => 'Нет доступных треков';

  @override
  String get errDrm => 'Трек защищён DRM';

  @override
  String get errNoStream => 'Нет данных потока';

  @override
  String get errTrackNotFound => 'Трек не найден';

  @override
  String get errScUnavailable => 'SoundCloud не отвечает';

  @override
  String get errScForbidden => 'SoundCloud: доступ запрещён';

  @override
  String get errScClientId => 'SoundCloud: client_id истёк';

  @override
  String get errYtmNoAudio => 'YouTube не вернул аудиопоток';

  @override
  String get errYtmNetwork => 'YouTube не отвечает';

  @override
  String get apFontCat => 'ШРИФТ';

  @override
  String get apFontTitle => 'Шрифт интерфейса';

  @override
  String get apFontDesc => 'Выберите шрифт для всего приложения';

  @override
  String get apFontAdd => 'Загрузить свой шрифт';

  @override
  String get apFontRemove => 'Удалить шрифт';

  @override
  String apFontAdded(int n) {
    return 'Шрифтов добавлено: $n';
  }

  @override
  String get apFontBadFormat => 'Подходят только .ttf и .otf';

  @override
  String apFontTooBig(int mb) {
    return 'Файл шрифта больше $mb МБ';
  }

  @override
  String get apFontReadErr => 'Не прочитать файл шрифта';

  @override
  String get setPc => 'Компьютер';

  @override
  String get pcNotPaired => 'Не подключён';

  @override
  String get pcPlayOn => 'Играть на';

  @override
  String get pcThisPhone => 'Этот телефон';

  @override
  String pcPairedTo(String name) {
    return 'Подключён к «$name»';
  }

  @override
  String pcSyncedAt(String when) {
    return 'Синхронизировано $when';
  }

  @override
  String get pcSyncing => 'Синхронизация…';

  @override
  String get pcOffline => 'Компьютер не в сети';

  @override
  String get pcRepair => 'Компьютер больше не узнаёт телефон — подключи заново';

  @override
  String get pcFailed => 'Не удалось синхронизировать';

  @override
  String get pcStep1 =>
      'Открой **Bloom** на компьютере: **Настройки → Интеграции → Телефон** и включи режим.';

  @override
  String get pcStep2 =>
      'Нажми **«Подключить телефон»** — появятся QR-код и шестизначный код.';

  @override
  String get pcStep3 =>
      'Здесь нажми **«Сканировать QR-код»** и наведи камеру — или **«Ввести код»**.';

  @override
  String get pcGuideNote =>
      'Телефон и компьютер должны быть в одной домашней сети. Синхронизируются плейлисты, лайки, подписки, дизлайки, история и профиль; настройки у каждого устройства свои.';

  @override
  String get pcScan => 'Сканировать QR-код';

  @override
  String get pcEnterCode => 'Ввести код';

  @override
  String get pcSyncNow => 'Синхронизировать сейчас';

  @override
  String get pcReconnect => 'Подключить заново';

  @override
  String get pcUnpair => 'Отключить';

  @override
  String get pcUnpairTitle => 'Отключить компьютер?';

  @override
  String pcUnpairBody(String name) {
    return 'Синхронизация с «$name» прекратится. Подключиться снова можно только с компьютера: «Подключить телефон» на его экране.';
  }

  @override
  String get pcUnpaired => 'Забыт. Отключи и на компьютере';

  @override
  String get pcScanHint => 'Наведи камеру на QR-код на экране компьютера';

  @override
  String get pcNoCamera => 'Нет доступа к камере';

  @override
  String get pcCodeSearching => 'Ищу компьютер…';

  @override
  String get pcCodeNone =>
      'Компьютер не найден. Открой на нём «Подключить телефон» — телефон должен быть в той же сети.';

  @override
  String get pcCodeRetry => 'Искать снова';

  @override
  String get pcCodeHint => 'Код с экрана компьютера';

  @override
  String get pcConnect => 'Подключить';

  @override
  String pcPaired(String name) {
    return 'Подключено к «$name»';
  }

  @override
  String get pcSynced => 'Синхронизировано';

  @override
  String get pcErrNotBloom => 'Это не код Bloom';

  @override
  String get pcErrUnreachable => 'Не отвечает. Та же сеть?';

  @override
  String get pcErrWrong => 'Неверный код';

  @override
  String get pcErrClosed => 'Окно на компьютере закрыто';

  @override
  String get pcErrTooMany => 'Много попыток, жди новый код';

  @override
  String get pcErrFailed => 'Не удалось подключить';

  @override
  String get taPlayNextHint => 'Сыграет после текущего';

  @override
  String get waveFromTrackHint => 'Подборка похожего';

  @override
  String get waveFromArtistHint => 'Подборка по артисту';

  @override
  String get waveDislikeHint => 'Не попадётся в подборках';

  @override
  String get waveUndislikeHint => 'Снова будет в подборках';

  @override
  String get tiHint => 'Альбом, год, длительность';

  @override
  String get tlOfflineHint => 'Копия в приложении';

  @override
  String get tlFilesHint => 'В файлы на телефон';

  @override
  String get tlRefreshHint => 'Новое из источников';

  @override
  String get commonPinHint => 'Первым в библиотеке';

  @override
  String get tlMergeHint => 'В новый плейлист';

  @override
  String get tlConvertHint => 'Копия на другой площадке';

  @override
  String get tlFindDupsHint => 'Повторы в этом списке';

  @override
  String get tlExportHint => 'В файл переноса';

  @override
  String get artistImportHint => 'В вашу библиотеку';

  @override
  String get commonFollowHint => 'Артист появится в библиотеке';
}
