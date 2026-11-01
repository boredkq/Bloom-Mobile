/// Where the app keeps its files. Two directories, not to be confused:
/// [appPrivateDir] is internal (`bloom.json`, playlist covers, offline copies);
/// [appVisibleDir] is what the user downloaded and must find. On iOS that's the
/// app's folder in Files; on Android downloads go to shared Music past it (see
/// `MediaStoreSaver`), so it's unused there.
///
/// Why: on iOS Files shows ALL of `Documents` with `UIFileSharingEnabled`, and
/// the user could wipe internal files. So on iOS they live in `Application
/// Support`, which Files can't see.
///
/// On Android the directory stays `Documents`, private to the app: existing
/// installs keep their library there.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Internal directory: library, covers, offline copies. Created if missing:
/// `Application Support` may not exist on a fresh iOS install, and the first
/// `bloom.json` write would silently go nowhere.
Future<Directory> appPrivateDir() async {
  final dir = Platform.isIOS
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// Directory the user sees in system Files (iOS).
Future<Directory> appVisibleDir() => getApplicationDocumentsDirectory();
