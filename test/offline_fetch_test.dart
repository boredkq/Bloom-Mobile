/// Downloading a track file: `Range` chunks and resuming a broken connection.
///
/// The platform is a fake HTTP server on a local port: I check what breaks when
/// a server cuts off mid-body ("Connection closed while receiving data"), with
/// no network involved.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bloom/features/offline/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "track" body: an m4a header (`....ftyp`), then predictable junk.
Uint8List _body(int size) {
  final bytes = Uint8List(size);
  bytes.setRange(0, 8, [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]);
  final rnd = Random(42);
  for (var i = 8; i < size; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return bytes;
}

/// A server giving [data] by `Range`.
///
/// [breakAt] is how many first answers to cut after half the promised body.
/// [deadAfter] is the answer from which it drops the connection with no bytes
/// at all: the download has nothing to hold on to and must give up.
/// [ignoreRange] is a platform that doesn't know `Range`: 200 and the whole
/// body.
Future<HttpServer> _serve(
  Uint8List data, {
  int breakAt = 0,
  int? deadAfter,
  bool ignoreRange = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var served = 0;
  server.listen((req) async {
    final res = req.response;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (ignoreRange || range == null) {
      res.statusCode = 200;
      res.headers.contentLength = data.length;
      res.add(data);
      await res.close();
      return;
    }

    final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
    final start = int.parse(m.group(1)!);
    if (start >= data.length) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await res.close();
      return;
    }
    final end = min(
      m.group(2)!.isEmpty ? data.length - 1 : int.parse(m.group(2)!),
      data.length - 1,
    );
    final part = data.sublist(start, end + 1);
    final n = served++;

    if (n < breakAt || (deadAfter != null && n >= deadAfter)) {
      // I write the headers by hand: `HttpResponse` won't let me cut the
      // connection after sending them itself.
      final socket = await res.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 206 Partial Content\r\n'
        'Content-Range: bytes $start-$end/${data.length}\r\n'
        'Content-Length: ${part.length}\r\n\r\n',
      );
      if (n < breakAt) socket.add(part.sublist(0, part.length ~/ 2));
      await socket.flush();
      socket.destroy();
      return;
    }

    res.statusCode = HttpStatus.partialContent;
    res.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/${data.length}',
    );
    res.headers.contentLength = part.length;
    res.add(part);
    await res.close();
  });
  return server;
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bloom_fetch');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<File> fetch(HttpServer server, {void Function(double)? onProgress}) =>
      fetchAudioToFile(
        url: 'http://${server.address.host}:${server.port}/track',
        headers: const {},
        dir: dir,
        base: 'Трек',
        onProgress: onProgress,
      );

  test('файл длиннее куска собирается целиком и в верном порядке', () async {
    final data = _body(3 * 1024 * 1024 + 777);
    final server = await _serve(data);
    addTearDown(() => server.close(force: true));

    final file = await fetch(server);
    expect(file.readAsBytesSync(), data);
    // The extension comes from the signature, not the URL, which has none.
    expect(file.path.endsWith('.m4a'), isTrue);
  });

  test('оборванное соединение докачивается с той же позиции', () async {
    final data = _body(3 * 1024 * 1024);
    final server = await _serve(data, breakAt: 2);
    addTearDown(() => server.close(force: true));

    final file = await fetch(server);
    expect(file.readAsBytesSync(), data);
  });

  test('прогресс доходит до единицы и не пятится', () async {
    final data = _body(2 * 1024 * 1024 + 5);
    final server = await _serve(data, breakAt: 1);
    addTearDown(() => server.close(force: true));

    final seen = <double>[];
    await fetch(server, onProgress: seen.add);
    expect(seen.last, closeTo(1, 0.0001));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('площадка без Range отдаёт файл одним ответом', () async {
    final data = _body(1500);
    final server = await _serve(data, ignoreRange: true);
    addTearDown(() => server.close(force: true));

    final file = await fetch(server);
    expect(file.readAsBytesSync(), data);
  });

  test('безнадёжный обрыв не оставляет огрызка в каталоге', () async {
    final data = _body(3 * 1024 * 1024);
    final server = await _serve(data, deadAfter: 0);
    addTearDown(() => server.close(force: true));

    await expectLater(fetch(server), throwsA(isA<Exception>()));
    expect(dir.listSync(), isEmpty);
  });
}
