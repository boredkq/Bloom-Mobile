/// Full user backup and cloud sync: favorites, playlists, listening level,
/// stats, follows, wave dislikes, profile, and settings.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../db/db.dart';
import '../log/bloom_log.dart';

const String kFullBackupVersion = '1.0';

/// Gathers the entire state of the user into a structured map for backup and sync.
Map<String, dynamic> buildFullBackup(BloomDb db) {
  // 1. Profile & level
  final profile = db.getMap('profile');
  final profileSince = db.get('profile.since');
  final bankedXp = db.get('level.banked');

  // Total play count and stats
  final playCount = db.value('SELECT count(*) FROM plays') as int? ?? 0;
  final dayCount = db.value('SELECT count(*) FROM days') as int? ?? 0;

  // 2. Favorites (tracks in 'fav' list)
  final favRows = db.select('''
    SELECT t.id, t.provider, t.title, t.artist, t.album, t.cover, t.duration, t.extra, t.updated_at, lt.pos
    FROM list_tracks lt
    JOIN tracks t ON t.id = lt.track_id
    WHERE lt.list_id = 'fav'
    ORDER BY lt.pos
  ''');
  final favorites = [
    for (final r in favRows)
      {
        'id': r['id'],
        'provider': r['provider'],
        'title': r['title'],
        'artist': r['artist'],
        'album': r['album'],
        'cover': r['cover'],
        'duration': r['duration'],
        'extra': r['extra'],
        'updated_at': r['updated_at'],
        'pos': r['pos'],
      },
  ];

  // 3. User playlists
  final listRows = db.select(
    "SELECT * FROM lists WHERE kind NOT IN ('lib', 'fav') ORDER BY side_pos",
  );
  final playlists = <Map<String, dynamic>>[];
  for (final l in listRows) {
    final listId = l['id'] as String;
    final trackRows = db.select(
      '''
      SELECT t.id, t.provider, t.title, t.artist, t.album, t.cover, t.duration, t.extra, t.updated_at, lt.pos
      FROM list_tracks lt
      JOIN tracks t ON t.id = lt.track_id
      WHERE lt.list_id = ?
      ORDER BY lt.pos
    ''',
      [listId],
    );

    playlists.add({
      'id': listId,
      'kind': l['kind'],
      'name': l['name'],
      'description': l['description'],
      'cover': l['cover'],
      'sources': l['sources'],
      'auto_refresh': l['auto_refresh'],
      'created_at': l['created_at'],
      'updated_at': l['updated_at'],
      'tracks': [
        for (final t in trackRows)
          {
            'id': t['id'],
            'provider': t['provider'],
            'title': t['title'],
            'artist': t['artist'],
            'album': t['album'],
            'cover': t['cover'],
            'duration': t['duration'],
            'extra': t['extra'],
            'updated_at': t['updated_at'],
            'pos': t['pos'],
          },
      ],
    });
  }

  // 4. Followed artists
  final follows = [
    for (final f in db.select('SELECT * FROM follows'))
      {
        'id': f['id'],
        'provider': f['provider'],
        'name': f['name'],
        'avatar': f['avatar'],
        'extra': f['extra'],
        'at': f['at'],
      },
  ];

  // 5. Dislikes
  final dislikes = [
    for (final d in db.select('SELECT * FROM dislikes'))
      {'track_id': d['track_id'], 'at': d['at']},
  ];

  // 6. Settings
  final settings = {
    'playerStyle': db.get('player.style'),
    'lyrics': db.get('lyrics'),
    'theme': db.get('theme'),
  };

  return {
    'version': kFullBackupVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'profile': profile,
    'level': {
      'bankedXp': bankedXp,
      'playCount': playCount,
      'dayCount': dayCount,
      'profileSince': profileSince,
    },
    'favorites': favorites,
    'playlists': playlists,
    'follows': follows,
    'dislikes': dislikes,
    'settings': settings,
  };
}

/// Applies a complete backup map, restoring favorites, playlists, level, and profile into SQLite.
bool applyFullBackup(BloomDb db, Map<String, dynamic> data) {
  try {
    db.tx(() {
      // 1. Profile & level
      if (data['profile'] case final Map<String, dynamic> prof) {
        db.set('profile', prof);
      }
      if (data['level'] case final Map<String, dynamic> lvl) {
        if (lvl['bankedXp'] != null) {
          db.set('level.banked', lvl['bankedXp']);
        }
        if (lvl['profileSince'] != null) {
          db.set('profile.since', lvl['profileSince']);
        }
      }

      // 2. Favorites
      if (data['favorites'] case final List favs) {
        final now = DateTime.now().millisecondsSinceEpoch;
        // Ensure 'fav' list exists
        db.exec(
          '''
          INSERT OR IGNORE INTO lists (id, kind, name, description, cover, sources, auto_refresh, created_at, updated_at)
          VALUES ('fav', 'fav', 'Избранное', '', '', '[]', 0, ?, ?)
        ''',
          [now, now],
        );

        for (var i = 0; i < favs.length; i++) {
          final t = favs[i];
          if (t is! Map) continue;
          final id = t['id'] as String? ?? '';
          if (id.isEmpty) continue;

          // Insert or update track
          db.exec(
            '''
            INSERT OR REPLACE INTO tracks (id, provider, title, artist, album, cover, duration, extra, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
            [
              id,
              t['provider'] ?? 'sc',
              t['title'] ?? '',
              t['artist'] ?? '',
              t['album'] ?? '',
              t['cover'] ?? '',
              t['duration'] ?? 0,
              t['extra'] is Map ? jsonEncode(t['extra']) : (t['extra'] ?? '{}'),
              t['updated_at'] ?? now,
            ],
          );

          // Link to 'fav' list
          db.exec(
            '''
            INSERT OR REPLACE INTO list_tracks (list_id, track_id, pos, added_at)
            VALUES ('fav', ?, ?, ?)
          ''',
            [id, t['pos'] ?? i, t['updated_at'] ?? now],
          );
        }
      }

      // 3. Playlists
      if (data['playlists'] case final List lists) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final l in lists) {
          if (l is! Map) continue;
          final listId = l['id'] as String? ?? '';
          if (listId.isEmpty) continue;

          db.exec(
            '''
            INSERT OR REPLACE INTO lists (id, kind, name, description, cover, sources, auto_refresh, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
            [
              listId,
              l['kind'] ?? 'custom',
              l['name'] ?? 'Плейлист',
              l['description'] ?? '',
              l['cover'] ?? '',
              l['sources'] is List
                  ? jsonEncode(l['sources'])
                  : (l['sources'] ?? '[]'),
              l['auto_refresh'] ?? 0,
              l['created_at'] ?? now,
              l['updated_at'] ?? now,
            ],
          );

          if (l['tracks'] case final List tracks) {
            for (var i = 0; i < tracks.length; i++) {
              final t = tracks[i];
              if (t is! Map) continue;
              final tid = t['id'] as String? ?? '';
              if (tid.isEmpty) continue;

              db.exec(
                '''
                INSERT OR REPLACE INTO tracks (id, provider, title, artist, album, cover, duration, extra, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
              ''',
                [
                  tid,
                  t['provider'] ?? 'sc',
                  t['title'] ?? '',
                  t['artist'] ?? '',
                  t['album'] ?? '',
                  t['cover'] ?? '',
                  t['duration'] ?? 0,
                  t['extra'] is Map
                      ? jsonEncode(t['extra'])
                      : (t['extra'] ?? '{}'),
                  t['updated_at'] ?? now,
                ],
              );

              db.exec(
                '''
                INSERT OR REPLACE INTO list_tracks (list_id, track_id, pos, added_at)
                VALUES (?, ?, ?, ?)
              ''',
                [listId, tid, t['pos'] ?? i, t['updated_at'] ?? now],
              );
            }
          }
        }
      }

      // 4. Follows
      if (data['follows'] case final List follows) {
        for (final f in follows) {
          if (f is! Map) continue;
          final id = f['id'] as String? ?? '';
          if (id.isEmpty) continue;
          db.exec(
            '''
            INSERT OR REPLACE INTO follows (id, provider, name, avatar, extra, at)
            VALUES (?, ?, ?, ?, ?, ?)
          ''',
            [
              id,
              f['provider'] ?? '',
              f['name'] ?? '',
              f['avatar'] ?? '',
              f['extra'] is Map ? jsonEncode(f['extra']) : (f['extra'] ?? '{}'),
              f['at'] ?? DateTime.now().millisecondsSinceEpoch,
            ],
          );
        }
      }

      // 5. Dislikes
      if (data['dislikes'] case final List dislikes) {
        for (final d in dislikes) {
          if (d is! Map) continue;
          final tid = d['track_id'] as String? ?? '';
          if (tid.isEmpty) continue;
          db.exec(
            '''
            INSERT OR REPLACE INTO dislikes (track_id, at)
            VALUES (?, ?)
          ''',
            [tid, d['at'] ?? DateTime.now().millisecondsSinceEpoch],
          );
        }
      }

      // 6. Settings
      if (data['settings'] case final Map<String, dynamic> s) {
        if (s['playerStyle'] != null) db.set('player.style', s['playerStyle']);
        if (s['lyrics'] != null) db.set('lyrics', s['lyrics']);
        if (s['theme'] != null) db.set('theme', s['theme']);
      }
    });

    logInfo('sync', 'Full backup applied successfully');
    return true;
  } catch (e, st) {
    logError('sync', 'Failed to apply full backup', e, st);
    return false;
  }
}

/// Sends complete user state to the Vercel backend.
Future<bool> pushBackupToVercel({
  required String serverUrl,
  required String userId,
  required BloomDb db,
}) async {
  try {
    final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanUrl/api/user/sync');
    final backup = buildFullBackup(db);

    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json', 'X-User-Id': userId},
          body: jsonEncode({'userId': userId, ...backup}),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      logInfo('sync', 'Cloud sync push success: ${res.body}');
      return true;
    }
    logWarn('sync', 'Cloud sync push failed: status ${res.statusCode}');
    return false;
  } catch (e) {
    logWarn('sync', 'Cloud sync push exception: $e');
    return false;
  }
}

/// Retrieves complete user state from the Vercel backend and applies it.
Future<bool> pullBackupFromVercel({
  required String serverUrl,
  required String userId,
  required BloomDb db,
}) async {
  try {
    final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$cleanUrl/api/user/sync?userId=${Uri.encodeComponent(userId)}',
    );

    final res = await http
        .get(uri, headers: {'Accept': 'application/json', 'X-User-Id': userId})
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      if (json is Map<String, dynamic> &&
          json['data'] is Map<String, dynamic>) {
        final applied = applyFullBackup(
          db,
          json['data'] as Map<String, dynamic>,
        );
        return applied;
      }
    }
    return false;
  } catch (e) {
    logWarn('sync', 'Cloud sync pull exception: $e');
    return false;
  }
}
