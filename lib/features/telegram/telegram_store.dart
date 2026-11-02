/// Telegram Authentication: login via Telegram Login Widget (Vercel Serverless)
/// or deep linking. Persisted in `bloom.json` under `telegram`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/db.dart';
import '../../core/store/json_store.dart';

class TelegramUser {
  final int id;
  final String firstName;
  final String? lastName;
  final String? username;
  final String? photoUrl;
  final int authDate;

  const TelegramUser({
    required this.id,
    required this.firstName,
    this.lastName,
    this.username,
    this.photoUrl,
    required this.authDate,
  });

  String get displayName {
    if (lastName case final last? when last.trim().isNotEmpty) {
      return '$firstName $last'.trim();
    }
    return firstName;
  }

  String? get handle => username != null ? '@$username' : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'first_name': firstName,
    if (lastName != null) 'last_name': lastName,
    if (username != null) 'username': username,
    if (photoUrl != null) 'photo_url': photoUrl,
    'auth_date': authDate,
  };

  factory TelegramUser.fromJson(Map<String, dynamic> json) {
    return TelegramUser(
      id: json['id'] is num
          ? (json['id'] as num).toInt()
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString(),
      username: json['username']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      authDate: json['auth_date'] is num
          ? (json['auth_date'] as num).toInt()
          : int.tryParse(json['auth_date']?.toString() ?? '0') ?? 0,
    );
  }
}

class TelegramAuthState {
  final bool authed;
  final TelegramUser? user;
  final bool connecting;
  final String? error;

  const TelegramAuthState({
    this.authed = false,
    this.user,
    this.connecting = false,
    this.error,
  });

  TelegramAuthState copyWith({
    bool? authed,
    TelegramUser? user,
    bool clearUser = false,
    bool? connecting,
    String? error,
    bool clearError = false,
  }) => TelegramAuthState(
    authed: authed ?? this.authed,
    user: clearUser ? null : (user ?? this.user),
    connecting: connecting ?? this.connecting,
    error: clearError ? null : (error ?? this.error),
  );
}

final telegramAuthProvider =
    NotifierProvider<TelegramAuthController, TelegramAuthState>(
      TelegramAuthController.new,
    );

class TelegramAuthController extends Notifier<TelegramAuthState> {
  static const String _storeKey = 'telegram';

  @override
  TelegramAuthState build() {
    final raw = ref.read(jsonStoreProvider).readMap(_storeKey);
    if (raw.isNotEmpty && raw['id'] != null) {
      try {
        final user = TelegramUser.fromJson(raw);
        return TelegramAuthState(authed: true, user: user);
      } catch (_) {
        // Corrupted entry
      }
    }
    return const TelegramAuthState();
  }

  /// Saves the Telegram user profile and optionally syncs it with Bloom's local profile.
  void loginWithData(Map<String, dynamic> data) {
    try {
      final user = TelegramUser.fromJson(data);
      ref.read(jsonStoreProvider).write(_storeKey, user.toJson());

      // Sync name into local profile if not custom
      try {
        final db = ref.read(dbProvider);
        final profile = db.getMap('profile');
        if (profile['name'] == null || profile['name'] == 'Слушатель') {
          db.setMap('profile', {
            ...profile,
            'name': user.displayName,
            if (user.photoUrl != null && profile['avatar'] == null)
              'avatar': user.photoUrl,
          });
        }
      } catch (_) {
        // Database not ready or in test environment
      }

      state = state.copyWith(
        authed: true,
        user: user,
        connecting: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        connecting: false,
        error: 'Не удалось обработать данные Telegram: $e',
      );
    }
  }

  /// Launch Telegram Login page in the browser
  Future<bool> startWebLogin(String vercelUrl) async {
    state = state.copyWith(connecting: true, clearError: true);
    final cleanUrl = vercelUrl.endsWith('/')
        ? '${vercelUrl}api/telegram/widget'
        : '$vercelUrl/api/telegram/widget';

    try {
      final uri = Uri.parse(cleanUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        state = state.copyWith(
          connecting: false,
          error: 'Не удалось открыть браузер для входа',
        );
      }
      return launched;
    } catch (e) {
      state = state.copyWith(connecting: false, error: '$e');
      return false;
    }
  }

  void cancelConnecting() {
    state = state.copyWith(connecting: false);
  }

  void logout() {
    ref.read(jsonStoreProvider).write(_storeKey, {});
    state = const TelegramAuthState();
  }
}
