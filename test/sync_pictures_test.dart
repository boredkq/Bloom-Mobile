/// Pictures in a sync packet ([SyncPictures]) and the pairing QR ([PairOffer]),
/// with no network.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/sync/pc_client.dart';
import 'package:bloom/core/sync/sync_pictures.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

Map<String, Object?> _payload(String cover, String avatar) => {
  'changes': [
    {
      'kind': 'list',
      'key': 'p1',
      'mod': 1,
      'device': 'x',
      'row': <String, Object?>{'kind': 'playlist', 'name': 'P', 'cover': cover},
    },
    {
      'kind': 'kv',
      'key': 'profile',
      'mod': 1,
      'device': 'x',
      'row': <String, Object?>{
        'value': jsonEncode([
          {'name': 'Me', 'avatar': avatar, 'banner': ''},
        ]),
      },
    },
    {'kind': 'list', 'key': 'gone', 'mod': 2, 'device': 'x', 'row': null},
  ],
  'tracks': [
    <String, Object?>{'id': 'sc:1', 'cover': 'https://i1.sndcdn.com/a.jpg'},
  ],
};

String _avatar(Map<String, Object?> p) {
  final row = ((p['changes'] as List)[1] as Map)['row'] as Map;
  return ((jsonDecode(row['value'] as String) as List).first as Map)['avatar']
      as String;
}

String _cover(Map<String, Object?> p) =>
    (((p['changes'] as List).first as Map)['row'] as Map)['cover'] as String;

void main() {
  late Directory dir;
  late BloomDb db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bloom_pics_');
    db = BloomDb.memory();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('name: hash of the bytes, extension by the first bytes', () {
    final name = pictureName(_png);
    expect(validPictureName(name), isTrue);
    expect(name.endsWith('.png'), isTrue);
    expect(
      pictureName(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2]),
      ).endsWith('.jpg'),
      isTrue,
    );
    expect(validPictureName('../x.png'), isFalse);
  });

  test(
    'own pictures go out as img:<name>, a platform picture as it is, a lost file as ""',
    () {
      File('${dir.path}/cover_1.png').writeAsBytesSync(_png);
      final p = _payload('local:cover_1.png', 'local:missing.png');
      final names = SyncPictures(db, dir.path).toWire(p);
      final name = pictureName(_png);
      expect(names, {name});
      expect(_cover(p), 'img:$name');
      expect(_avatar(p), '');
      expect(
        ((p['tracks'] as List).first as Map)['cover'],
        'https://i1.sndcdn.com/a.jpg',
      );
      expect((p['changes'] as List)[2], containsPair('row', null));
    },
  );

  test('incoming: a picture we have becomes ours, one we lack becomes ""', () {
    final name = pictureName(_png);
    final pics = SyncPictures(db, dir.path);
    final p = _payload('img:$name', 'img:$name');
    expect(pics.wanted(p), {name});
    expect(pics.has(name), isFalse);
    pics.fromWire(p);
    expect(_cover(p), '');

    expect(pics.put(name, Uint8List.fromList([1, 2, 3])), isFalse);
    expect(pics.put(name, _png), isTrue);
    final again = _payload('img:$name', 'img:$name');
    pics.fromWire(again);
    expect(_cover(again), 'local:$name');
    expect(_avatar(again), 'local:$name');
  });

  test('a picture already ours under another file name is found by the rows', () {
    File('${dir.path}/cover_7.png').writeAsBytesSync(_png);
    db.exec(
      "INSERT INTO lists (id, kind, name, cover, created_at, updated_at) VALUES ('l', 'playlist', 'L', 'local:cover_7.png', 1, 1)",
    );
    final name = pictureName(_png);
    final pics = SyncPictures(db, dir.path);
    expect(pics.has(name), isTrue);
    expect(pics.read(name), _png);
    final p = _payload('img:$name', '');
    pics.fromWire(p);
    expect(_cover(p), 'local:cover_7.png');
  });

  test('the QR of the PC', () {
    final o = PairOffer.parse(
      '{"bloom":"pair","v":1,"a":["192.168.0.4","10.0.0.2"],"p":49410,"s":"abc","f":"def"}',
    )!;
    expect(o.addresses, ['192.168.0.4', '10.0.0.2']);
    expect(o.port, 49410);
    expect((o.secret, o.print), ('abc', 'def'));
    expect(PairOffer.parse('https://example.com'), isNull);
    expect(
      PairOffer.parse('{"bloom":"pair","v":2,"a":["1"],"p":1,"s":"","f":""}'),
      isNull,
    );
  });

  test('a link keeps where the PC answered first', () {
    const link = PcLink(
      device: 'd',
      name: 'PC',
      token: 't',
      print: 'f',
      addresses: ['a', 'b'],
      port: 1,
    );
    final moved = link.at('b', 2);
    expect(moved.addresses, ['b', 'a']);
    expect(moved.port, 2);
    expect(PcLink.fromJson(moved.toJson())!.addresses, ['b', 'a']);
  });
}
