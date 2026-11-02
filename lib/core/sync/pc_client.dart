/// Link to a computer on the home network: pairing by QR or code, TLS with its
/// pinned certificate, finding it when its address changed.
///
/// The phone drives every round; the computer only hints through its event
/// stream ([PcClient.events]) that it has something new.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Discovery port, the first of the computer's home network ports.
const int kFindPort = 49410;

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Certificate print, as `f` in the QR: SHA-256 of DER, base64url with no `=`.
String certPrint(X509Certificate cert) =>
    _b64url(sha256.convert(cert.der).bytes);

/// What the QR on the computer's screen shows:
/// `{"bloom":"pair","v":1,"a":[addresses],"p":port,"s":secret,"f":print}`.
class PairOffer {
  const PairOffer({
    required this.addresses,
    required this.port,
    required this.secret,
    required this.print,
  });

  final List<String> addresses;
  final int port;
  final String secret;
  final String print;

  /// `null` if it isn't a Bloom QR.
  static PairOffer? parse(String text) {
    Object? doc;
    try {
      doc = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (doc is! Map || doc['bloom'] != 'pair' || doc['v'] != 1) return null;
    final a = doc['a'], p = doc['p'], s = doc['s'], f = doc['f'];
    if (a is! List || p is! int || s is! String || f is! String) return null;
    final addresses = [
      for (final x in a)
        if (x is String && x.isNotEmpty) x,
    ];
    if (addresses.isEmpty) return null;
    return PairOffer(addresses: addresses, port: p, secret: s, print: f);
  }
}

/// A paired computer: who it is, where it last was, what proves it ([print])
/// and this phone's key ([token]). Stored in kv `sync.pc`.
class PcLink {
  const PcLink({
    required this.device,
    required this.name,
    required this.token,
    required this.print,
    required this.addresses,
    required this.port,
  });

  final String device;
  final String name;
  final String token;
  final String print;

  /// Where it answered; the last answering one first.
  final List<String> addresses;
  final int port;

  PcLink at(String address, int port) => PcLink(
    device: device,
    name: name,
    token: token,
    print: print,
    addresses: [
      address,
      for (final a in addresses)
        if (a != address) a,
    ],
    port: port,
  );

  Map<String, Object?> toJson() => {
    'device': device,
    'name': name,
    'token': token,
    'f': print,
    'a': addresses,
    'p': port,
  };

  static PcLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final d = json['device'], n = json['name'], t = json['token'];
    final f = json['f'], a = json['a'], p = json['p'];
    if (d is! String ||
        t is! String ||
        f is! String ||
        a is! List ||
        p is! num) {
      return null;
    }
    return PcLink(
      device: d,
      name: n is String ? n : '',
      token: t,
      print: f,
      addresses: [
        for (final x in a)
          if (x is String) x,
      ],
      port: p.toInt(),
    );
  }
}

/// A computer that answered discovery.
class FoundPc {
  const FoundPc({
    required this.address,
    required this.port,
    required this.device,
    required this.name,
  });

  final String address;
  final int port;
  final String device;
  final String name;
}

/// A non-2xx answer.
class PcHttpError implements Exception {
  const PcHttpError(this.status, this.code);

  final int status;

  /// `error` from the answer: `wrong`, `not_pairing`, `too_many`,
  /// `unauthorized`…
  final String code;

  @override
  String toString() => 'PcHttpError($status, $code)';
}

/// The certificate isn't the pinned one: another computer, or its data was
/// reset.
class PcPrintMismatch implements Exception {
  const PcPrintMismatch();
}

/// One computer at one address. [print] is the pinned print; `null` is a first
/// meeting by code: I take whatever certificate comes and remember it in
/// [seen].
class PcClient {
  PcClient(this.address, this.port, {this.print, this.token});

  final String address;
  final int port;
  final String? print;
  final String? token;

  /// Print of the certificate seen in the last request.
  String? seen;

  Future<Map<String, Object?>> json(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final bytes = await send(
      method,
      path,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      timeout: timeout,
    );
    final doc = jsonDecode(utf8.decode(bytes));
    return doc is Map<String, Object?> ? doc : <String, Object?>{};
  }

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    // The certificate is self-signed: I don't check the chain, only the print.
    ..badCertificateCallback = (cert, _, _) =>
        print == null || certPrint(cert) == print;

  Future<HttpClientResponse> _open(
    HttpClient client,
    String method,
    String path,
    List<int>? body,
    Duration timeout,
  ) async {
    final req = await client
        .openUrl(
          method,
          Uri(scheme: 'https', host: address, port: port, path: path),
        )
        .timeout(timeout);
    // The server knows only Content-Length, not chunked.
    req.contentLength = body?.length ?? 0;
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = path.startsWith('/v1/sync/picture/')
          ? ContentType.binary
          : ContentType.json;
      req.add(body);
    }
    final res = await req.close().timeout(timeout);
    final cert = res.certificate;
    if (cert == null) throw const PcPrintMismatch();
    seen = certPrint(cert);
    if (print != null && seen != print) throw const PcPrintMismatch();
    return res;
  }

  Future<Uint8List> send(
    String method,
    String path, {
    List<int>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = _client();
    try {
      final res = await _open(client, method, path, body, timeout);
      final out = BytesBuilder(copy: false);
      await res.forEach(out.add).timeout(timeout);
      final data = out.takeBytes();
      if (res.statusCode >= 300) {
        var code = '';
        try {
          final doc = jsonDecode(utf8.decode(data));
          if (doc is Map && doc['error'] is String) {
            code = doc['error'] as String;
          }
        } catch (_) {}
        throw PcHttpError(res.statusCode, code);
      }
      return data;
    } on HandshakeException {
      // The print didn't match: badCertificateCallback said no.
      throw const PcPrintMismatch();
    } finally {
      client.close(force: true);
    }
  }

  /// The computer's event stream (`GET /v1/events`, SSE), held while listened
  /// to. Ends when it closes the connection, or with an error if silent longer
  /// than [silence] (it pings every 15 s), meaning the link died quietly.
  Stream<PcEvent> events({
    Duration silence = const Duration(seconds: 40),
  }) async* {
    final client = _client();
    try {
      final HttpClientResponse res;
      try {
        res = await _open(
          client,
          'GET',
          '/v1/events',
          null,
          const Duration(seconds: 5),
        );
      } on HandshakeException {
        throw const PcPrintMismatch();
      }
      if (res.statusCode >= 300) {
        await res.drain<void>();
        throw PcHttpError(res.statusCode, '');
      }
      var name = '';
      final data = StringBuffer();
      await for (final line
          in res
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(silence)) {
        if (line.isEmpty) {
          if (name.isNotEmpty) {
            Object? doc;
            try {
              doc = jsonDecode(data.toString());
            } catch (_) {}
            yield (
              name: name,
              data: doc is Map<String, Object?> ? doc : <String, Object?>{},
            );
          }
          name = '';
          data.clear();
        } else if (line.startsWith('event:')) {
          name = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trimLeft());
        }
        // `:` is a ping; nothing else in SSE is needed.
      }
    } finally {
      client.close(force: true);
    }
  }
}

/// An event from the stream: `player`, `position`, `queue`, `sync`…
typedef PcEvent = ({String name, Map<String, Object?> data});

/// Pairing: [secret] from the QR (certificate checked against its `f` before
/// sending) or [code] from the computer's screen (the certificate seen now gets
/// pinned). The address is the first of [addresses] to respond. Its error is a
/// [PcHttpError] (`wrong`, `not_pairing`, `too_many`); nobody responded is
/// `null`.
Future<PcLink?> pairPc({
  required List<String> addresses,
  required int port,
  String? print,
  String? secret,
  String? code,
  required String name,
  required String device,
}) async {
  // Who answers: with no key it says 401, which means it's there.
  Future<String?> probe(String a) async {
    try {
      await PcClient(
        a,
        port,
        print: print,
      ).send('GET', '/v1', timeout: const Duration(seconds: 4));
      return a;
    } on PcHttpError {
      return a;
    } catch (_) {
      return null;
    }
  }

  final alive = (await Future.wait(addresses.map(probe))).nonNulls;
  if (alive.isEmpty) return null;
  final client = PcClient(alive.first, port, print: print);
  final res = await client.json(
    'POST',
    '/v1/pair',
    body: {'secret': ?secret, 'code': ?code, 'name': name, 'device': device},
  );
  final pc = res['pc'];
  final token = res['token'];
  if (token is! String || pc is! Map || pc['device'] is! String) {
    throw const PcHttpError(0, 'bad_reply');
  }
  return PcLink(
    device: pc['device'] as String,
    name: pc['name'] is String ? pc['name'] as String : '',
    token: token,
    print: print ?? client.seen!,
    addresses: [
      alive.first,
      for (final a in addresses)
        if (a != alive.first) a,
    ],
    port: port,
  );
}

/// Finds computers on the network: broadcast and to [to]. With [print] only the
/// one with that certificate answers; without it, only one with the Connect
/// phone window open (pairing by code).
Future<List<FoundPc>> findPcs({
  String? print,
  Iterable<String> to = const [],
  Duration wait = const Duration(milliseconds: 1500),
}) async {
  final found = <String, FoundPc>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final msg = utf8.encode(jsonEncode({'bloom': 'find', 'f': ?print}));
    final done = Completer<void>();
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = socket!.receive();
      if (d == null) return;
      try {
        final o = jsonDecode(utf8.decode(d.data));
        if (o is Map &&
            o['bloom'] == 'here' &&
            o['p'] is int &&
            o['d'] is String) {
          found[o['d'] as String] = FoundPc(
            address: d.address.address,
            port: o['p'] as int,
            device: o['d'] as String,
            name: o['n'] is String ? o['n'] as String : '',
          );
        }
      } catch (_) {}
    });
    for (final target in {'255.255.255.255', ...to}) {
      try {
        socket.send(msg, InternetAddress(target), kFindPort);
      } catch (_) {
        // An address from another network or with no route: I try the rest.
      }
    }
    unawaited(Future<void>.delayed(wait).then((_) => done.complete()));
    await done.future;
    await sub.cancel();
  } catch (_) {
    // No network, so nobody found.
  } finally {
    socket?.close();
  }
  return found.values.toList();
}
