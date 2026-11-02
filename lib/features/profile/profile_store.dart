/// App user profile. It holds ONLY the card's data: nick, bio, status, pictures
/// and their colours. No play counters: stats come from the log.
///
/// It lies in database kv under `profile` (colours as "#rrggbb", cover mode as
/// a string), the first launch time in `profile.since`. A settings reset leaves
/// it alone, and reset everything takes it with the database. Avatar and banner
/// are files in the app's directory, with only `local:<name>` here: the iOS
/// container moves between launches, and an absolute path points nowhere
/// tomorrow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/l10n/l10n.dart';

/// Profile banner with no picture: the tone of the most played track's cover
/// (default), a solid colour or a gradient between two.
enum BannerColorMode { auto, solid, gradient }

/// Gradient angles for the banner.
const List<int> kBannerAngles = [0, 45, 90, 135, 180, 225, 270, 315];

/// Field lengths: nick, about, status.
const int kNickMax = 32;
const int kBioMax = 300;
const int kStatusMax = 80;

const Color _kBannerColor = Color(0xFF1A1A1A);
const Color _kBannerColor2 = Color(0xFF0D0D0D);

const String _kCard = 'profile';
const String _kSince = 'profile.since';

@immutable
class UserProfile {
  /// Display name. An empty field means nobody set one, and the localized
  /// default fills in. At paint rather than save time, or the default freezes
  /// in the first launch's language.
  String displayName(AppLocalizations l) =>
      name.trim().isEmpty ? l.profileDefaultName : name;

  const UserProfile({
    this.name = '',
    this.bio = '',
    this.status = '',
    this.bannerColor = _kBannerColor,
    this.bannerColor2 = _kBannerColor2,
    this.bannerMode = BannerColorMode.auto,
    this.bannerAngle = 135,
    this.avatar,
    this.banner,
  });

  final String name;
  final String bio;
  final String status;

  final Color bannerColor;
  final Color bannerColor2;
  final BannerColorMode bannerMode;
  final int bannerAngle;

  /// `local:<file name>` of an own picture; `null` is the stand-in figure.
  final String? avatar;

  /// `local:<file name>` of an own banner; `null` is colour, gradient or tone.
  final String? banner;

  /// Whether there's anything to show in the box under the nick.

  UserProfile copyWith({
    String? name,
    String? bio,
    String? status,
    Color? bannerColor,
    Color? bannerColor2,
    BannerColorMode? bannerMode,
    int? bannerAngle,
    String? avatar,
    bool clearAvatar = false,
    String? banner,
    bool clearBanner = false,
  }) => UserProfile(
    name: name ?? this.name,
    bio: bio ?? this.bio,
    status: status ?? this.status,
    bannerColor: bannerColor ?? this.bannerColor,
    bannerColor2: bannerColor2 ?? this.bannerColor2,
    bannerMode: bannerMode ?? this.bannerMode,
    bannerAngle: bannerAngle ?? this.bannerAngle,
    avatar: clearAvatar ? null : (avatar ?? this.avatar),
    banner: clearBanner ? null : (banner ?? this.banner),
  );

  /// Empty pictures as an empty string, not a missing field.
  Map<String, dynamic> toJson() => {
    'name': name,
    'bio': bio,
    'status': status,
    'avatar': avatar ?? '',
    'banner': banner ?? '',
    'bannerMode': bannerMode.name,
    'bannerColor': hexOf(bannerColor),
    'bannerColor2': hexOf(bannerColor2),
    'bannerAngle': bannerAngle,
  };

  /// From kv (or, later, another device), whole: what's missing or wrong takes
  /// the default, and text is cut to field lengths.
  static UserProfile fromJson(Map<String, dynamic> json) {
    String text(String key, int max) {
      final s = (json[key] as String? ?? '').trim();
      return s.characters.take(max).toString();
    }

    String? file(String key) {
      final raw = json[key];
      return raw is String && raw.isNotEmpty ? raw : null;
    }

    final angle = (json['bannerAngle'] as num?)?.toInt() ?? 135;
    return UserProfile(
      name: text('name', kNickMax),
      bio: text('bio', kBioMax),
      status: text('status', kStatusMax),
      bannerColor: colorOf(json['bannerColor']) ?? _kBannerColor,
      bannerColor2: colorOf(json['bannerColor2']) ?? _kBannerColor2,
      bannerMode:
          BannerColorMode.values.asNameMap()[json['bannerMode']] ??
          BannerColorMode.auto,
      bannerAngle: (angle % 360 + 360) % 360,
      avatar: file('avatar'),
      banner: file('banner'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.name == name &&
      other.bio == bio &&
      other.status == status &&
      other.bannerColor == bannerColor &&
      other.bannerColor2 == bannerColor2 &&
      other.bannerMode == bannerMode &&
      other.bannerAngle == bannerAngle &&
      other.avatar == avatar &&
      other.banner == banner;

  @override
  int get hashCode => Object.hash(
    name,
    bio,
    status,
    bannerColor,
    bannerColor2,
    bannerMode,
    bannerAngle,
    avatar,
    banner,
  );
}

/// "#rrggbb".
String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// "#rgb" or "#rrggbb" to a colour; anything else is `null`.
Color? colorOf(Object? raw) {
  if (raw is! String || !raw.startsWith('#')) return null;
  var hex = raw.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

final profileProvider = NotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
);

class ProfileController extends Notifier<UserProfile> {
  BloomDb get _db => ref.read(dbProvider);

  @override
  UserProfile build() {
    // The home header reads the profile at launch: that's when member since
    // gets set, not on the first visit to the profile page.
    ref.read(profileSinceProvider);
    return UserProfile.fromJson(_db.getMap(_kCard));
  }

  /// Re-reads from kv: a profile came from another device.
  void reload() => state = UserProfile.fromJson(_db.getMap(_kCard));

  /// Writes the whole profile: edits go as a draft in the editor and arrive
  /// here in one piece on Save. Written normalized, as it'll read next time.
  void save(UserProfile profile) {
    final card = UserProfile.fromJson(profile.toJson());
    if (card == state) return;
    _db.set(_kCard, card.toJson());
    state = card;
  }
}

/// When Bloom first ran on this device, for member since. Set at first read;
/// reset everything erases it too.
final profileSinceProvider = Provider<DateTime>((ref) {
  final db = ref.read(dbProvider);
  var ms = (db.get(_kSince, 0) as num?)?.toInt() ?? 0;
  if (ms <= 0) {
    ms = BloomDb.now();
    db.set(_kSince, ms);
  }
  return DateTime.fromMillisecondsSinceEpoch(ms);
});
