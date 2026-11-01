/// Hands the review's poster to the system's share sheet: from there it goes
/// to a chat or a story in one tap, and saving is in the same sheet.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const MethodChannel _channel = MethodChannel('bloom/files');

/// The temporary folder: on Android that's what the file provider can hand
/// out (`res/xml/bloom_share_paths.xml`). The system reads the file after the
/// call returns, so it stays; the next share overwrites it.
Future<File> _shareFile(String name) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/share');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return File('${dir.path}/$name');
}

/// False when it couldn't be handed over. Cancelling the sheet is a success.
Future<bool> shareImageBytes(
  Uint8List png, {
  required String filename,
  String? text,
}) async {
  try {
    final file = await _shareFile(filename);
    await file.writeAsBytes(png, flush: true);
    await _channel.invokeMethod<void>('shareFile', {
      'path': file.path,
      'mime': 'image/png',
      'text': ?text,
    });
    return true;
  } catch (_) {
    return false;
  }
}
