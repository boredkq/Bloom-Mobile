/// Yandex Music auth (OAuth device-flow). `authed` is a synchronous flag, by
/// which `YandexProvider.isEnabled` decides whether the platform shows in
/// search and the picker. The token lies in `bloom.json` under `yandex`, in the
/// clear, and goes to the network layer through `ym.setToken`.
///
/// Device-flow: [YmAuthController.startAuth] gets a code, opens the
/// confirmation page and polls for a token with a race token `_pollGen`: logout
/// or a new start cancels the last cycle.
///
/// No texts here: state carries a typed reason ([YmAuthNote]), and the settings
/// screen builds the phrase.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;
import 'models.dart';
import 'yandex.dart' as ym;
import 'ym_provider.dart' show clearYmStreamCache;

enum YmAuthNoteKind {
  /// Asking for a device code.
  gettingCode,

  /// The code shows, waiting for confirmation in the browser.
  waiting,

  /// The code expired: connect again.
  codeExpired,

  /// A platform refusal; [YmAuthNote.errorCode] is a `ym.err.*` code or its
  /// text.
  error,
}

class YmAuthNote {
  final YmAuthNoteKind kind;
  final String? errorCode;
  const YmAuthNote(this.kind, [this.errorCode]);
}

class YmAuthState {
  /// There's a saved token.
  final bool authed;

  /// Whether Yandex Plus is active. null: unchecked or unknown.
  final bool? hasPlus;

  /// A status check is running.
  final bool checking;

  /// Device-flow is running (a code got or shown).
  final bool connecting;
  final String? userCode;
  final String? verifyUrl;
  final YmAuthNote? note;

  const YmAuthState({
    this.authed = false,
    this.hasPlus,
    this.checking = false,
    this.connecting = false,
    this.userCode,
    this.verifyUrl,
    this.note,
  });

  YmAuthState copyWith({
    bool? authed,
    bool? hasPlus,
    bool clearPlus = false,
    bool? checking,
    bool? connecting,
    String? userCode,
    String? verifyUrl,
    bool clearCode = false,
    YmAuthNote? note,
    bool clearNote = false,
  }) => YmAuthState(
    authed: authed ?? this.authed,
    hasPlus: clearPlus ? null : (hasPlus ?? this.hasPlus),
    checking: checking ?? this.checking,
    connecting: connecting ?? this.connecting,
    userCode: clearCode ? null : (userCode ?? this.userCode),
    verifyUrl: clearCode ? null : (verifyUrl ?? this.verifyUrl),
    note: clearNote ? null : (note ?? this.note),
  );
}

final ymAuthProvider = NotifierProvider<YmAuthController, YmAuthState>(
  YmAuthController.new,
);

class YmAuthController extends Notifier<YmAuthState> {
  /// Polling race token: logout or a new start cancels the old cycle.
  int _pollGen = 0;

  @override
  YmAuthState build() {
    final raw = ref.read(jsonStoreProvider).readMap('yandex');
    final token = raw['token'];
    // The network layer keeps the token in module state, so at launch it gets
    // the saved one, or the provider stays off until login.
    ym.setToken(token is String ? token : null);
    return YmAuthState(authed: ym.activeToken() != null);
  }

  /// Device id stable between launches, random once and kept beside the token.
  /// Yandex doesn't validate it, only stability matters.
  String _deviceId() {
    final store = ref.read(jsonStoreProvider);
    final raw = store.readMap('yandex');
    final saved = raw['deviceId'];
    if (saved is String && saved.length >= 16) return saved;
    final rnd = Random.secure();
    final id = [
      for (var i = 0; i < 8; i++)
        rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    store.write('yandex', {...raw, 'deviceId': id});
    return id;
  }

  void _saveToken(String? token) {
    final store = ref.read(jsonStoreProvider);
    final next = {...store.readMap('yandex')};
    if (token == null) {
      next.remove('token');
    } else {
      next['token'] = token;
    }
    store.write('yandex', next);
    ym.setToken(token);
  }

  /// Re-reads the subscription status. An error doesn't count as logout: a 401
  /// may come from a failure, and silently throwing the user out is worse than
  /// status unknown; they can log out by a button.
  Future<void> refresh() async {
    if (!state.authed) {
      state = state.copyWith(checking: false, clearPlus: true);
      return;
    }
    state = state.copyWith(checking: true);
    try {
      final plus = await ym.hasPlus();
      state = state.copyWith(checking: false, hasPlus: plus, clearNote: true);
    } catch (e) {
      state = state.copyWith(
        checking: false,
        clearPlus: true,
        note: YmAuthNote(YmAuthNoteKind.error, '$e'),
      );
    }
  }

  /// Starts device-flow: a code, opening the confirmation page, polling for a
  /// token.
  Future<void> startAuth() async {
    _pollGen++; // cancels the last poll
    state = state.copyWith(
      connecting: true,
      clearCode: true,
      note: const YmAuthNote(YmAuthNoteKind.gettingCode),
    );
    try {
      final d = await ym.authStart(_deviceId());
      state = state.copyWith(
        userCode: d.userCode,
        verifyUrl: d.verificationUrl,
        note: const YmAuthNote(YmAuthNoteKind.waiting),
      );
      // The confirmation page opens in a browser: there's nowhere to show it,
      // and the code goes to Yandex ID anyway. If it doesn't open, code and
      // address show on screen for doing it by hand.
      unawaited(openVerifyPage(d.verificationUrl));

      final gen = ++_pollGen;
      final deadline = DateTime.now().add(d.expiresIn);
      // Yandex counts under 3 seconds between polls as slow_down.
      final step = d.interval < const Duration(seconds: 3)
          ? const Duration(seconds: 3)
          : d.interval;
      unawaited(_poll(gen, d.deviceCode, deadline, step));
    } catch (e) {
      state = state.copyWith(
        connecting: false,
        clearCode: true,
        note: YmAuthNote(YmAuthNoteKind.error, '$e'),
      );
    }
  }

  Future<void> _poll(
    int gen,
    String deviceCode,
    DateTime deadline,
    Duration step,
  ) async {
    while (true) {
      if (gen != _pollGen) return; // cancelled
      if (DateTime.now().isAfter(deadline)) {
        state = state.copyWith(
          connecting: false,
          clearCode: true,
          note: const YmAuthNote(YmAuthNoteKind.codeExpired),
        );
        return;
      }
      try {
        final r = await ym.authPoll(deviceCode);
        if (gen != _pollGen) return;
        if (!r.isPending) {
          _saveToken(r.token);
          state = state.copyWith(
            authed: true,
            connecting: false,
            clearCode: true,
            clearNote: true,
          );
          await refresh();
          return;
        }
      } catch (e) {
        if (gen != _pollGen) return;
        state = state.copyWith(
          connecting: false,
          clearCode: true,
          note: YmAuthNote(YmAuthNoteKind.error, '$e'),
        );
        return;
      }
      await Future<void>.delayed(step);
    }
  }

  /// Stops polling (leaving the screen, a new login).
  void cancelAuth() {
    _pollGen++;
    state = state.copyWith(connecting: false, clearCode: true, clearNote: true);
  }

  /// Direct login with an access token (e.g. from Vercel OAuth callback or user input).
  Future<bool> loginWithToken(String token) async {
    final clean = token.trim();
    if (clean.isEmpty) return false;
    _pollGen++;
    _saveToken(clean);
    state = state.copyWith(
      authed: true,
      connecting: false,
      clearCode: true,
      clearNote: true,
    );
    await refresh();
    return state.authed;
  }

  /// Logs out: the token is deleted and the platform leaves search.
  void logout() {
    _pollGen++; // stops polling
    _saveToken(null);
    clearYmStreamCache();
    state = const YmAuthState();
  }
}

/// Opens the confirmation page. A separate function, so tests can swap it and
/// leave the browser alone.
Future<bool> Function(String url) openVerifyPage = (url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
};

/// A refusal's reason for the UI: a `ym.err.*` code or the platform's text.
String ymErrorCode(Object error) {
  final s = error is YmException ? error.code : '$error';
  return s.startsWith('YmException: ') ? s.substring(13) : s;
}
