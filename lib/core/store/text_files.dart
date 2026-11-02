/// System dialogs for saving text as a file and opening a text file. My own
/// `MethodChannel`, as with notifications and downloads: no package for one
/// system screen per side.
///
/// Android uses SAF (`ACTION_CREATE_DOCUMENT`, `ACTION_OPEN_DOCUMENT`): the
/// user picks the place, with no storage permission needed. iOS uses
/// `UIDocumentPicker`.
///
/// `null` or `false` means the dialog was closed, not an error.
///
/// Three users: customization presets (`.bloompresets`), playlist transfer
/// (`.bloomplaylist`) and log export.
library;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('bloom/files');

/// Offers to save text as a file. `true` if written, `false` if cancelled or
/// failed.
Future<bool> saveTextFile(
  String filename,
  String content, {
  String mime = 'application/json',
}) async {
  try {
    final ok = await _channel.invokeMethod<bool>('saveText', {
      'filename': filename,
      'content': content,
      // `.bloompresets` and `.bloomplaylist` have no types of their own;
      // `application/json` makes the system's folder picker offer a sensible
      // place.
      'mime': mime,
    });
    return ok ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false; // a platform with no native side (tests)
  }
}

/// Lets the user pick a file and reads it. `null` if cancelled or unreadable.
Future<String?> openTextFile() async {
  try {
    return await _channel.invokeMethod<String>('openText');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// App name and build, for the version row in About. Native rather than a
/// package: one manifest read per side, not worth a dependency.
///
/// `null`: the platform didn't answer (tests).
Future<({String version, String build})?> appVersion() async {
  final info = await _appInfo();
  final version = info?['version'];
  if (version is! String || version.isEmpty) return null;
  return (version: version, build: '${info?['build'] ?? ''}');
}

/// The phone's name, for the computer's list of connected devices. The same
/// platform answer as [appVersion]; `null` if it didn't answer.
Future<String?> deviceName() async {
  final name = (await _appInfo())?['device'];
  return name is String && name.trim().isNotEmpty ? name.trim() : null;
}

Future<Map<String, Object?>?> _appInfo() async {
  try {
    return await _channel.invokeMapMethod<String, Object?>('appInfo');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
