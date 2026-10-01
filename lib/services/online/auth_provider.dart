import 'dart:math';

import 'package:flutter/foundation.dart';

import '../prefs_store.dart';

/// Thrown when no way to sign in exists in this build.
class AuthUnavailable implements Exception {
  const AuthUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Supplies the token sent in `hello`. The real implementation (Firebase
/// anonymous auth) arrives with the Firebase project in the next stage.
abstract class AuthTokenProvider {
  /// A token the server accepts. Throws [AuthUnavailable].
  Future<String> idToken({bool forceRefresh = false});

  /// A stable id for logs and the UI (the real one comes from the token).
  String? get debugUid;
}

/// DEBUG BUILDS ONLY. Produces `test:<uid>` tokens for a server started with
/// `NAWTIN_TEST_AUTH=1`, so online play can be tried with no Firebase setup.
///
/// The uid is kept per install (two emulators get two players). Override it
/// with `--dart-define=NAWTIN_DEV_UID=alice` to impersonate a fixed id.
///
/// Compiled out of release builds: [createAuth] only constructs this when
/// `kDebugMode` is true, and the constructor asserts it as well.
class DebugFakeAuth implements AuthTokenProvider {
  DebugFakeAuth(this._uid) {
    assert(kDebugMode, 'DebugFakeAuth must never run in a release build');
  }

  final String _uid;

  static const _define = String.fromEnvironment('NAWTIN_DEV_UID');

  /// Loads (or creates and stores) this install's fake uid.
  factory DebugFakeAuth.forInstall(PrefsStore store, Random random) {
    if (_define.isNotEmpty) return DebugFakeAuth(_define);
    var uid = store.read('debug.uid');
    if (uid == null || uid.isEmpty) {
      uid = 'dev-${random.nextInt(1 << 30).toRadixString(36)}';
      store.write('debug.uid', uid);
    }
    return DebugFakeAuth(uid);
  }

  @override
  String? get debugUid => _uid;

  @override
  Future<String> idToken({bool forceRefresh = false}) async => 'test:$_uid';
}

/// What release builds use until real sign-in is wired up: online play simply
/// reports itself unavailable. It never invents a token.
class UnavailableAuth implements AuthTokenProvider {
  const UnavailableAuth();

  @override
  String? get debugUid => null;

  @override
  Future<String> idToken({bool forceRefresh = false}) =>
      Future.error(const AuthUnavailable('Online sign-in is not available in this build.'));
}

/// Picks the auth for this build. The fake-token path exists only when
/// [debug] is true; with `debug: false` (every release build) it cannot be
/// reached.
AuthTokenProvider createAuth({
  required bool debug,
  required PrefsStore store,
  required Random random,
  AuthTokenProvider? real,
}) {
  if (real != null) return real;
  if (debug) return DebugFakeAuth.forInstall(store, random);
  return const UnavailableAuth();
}
