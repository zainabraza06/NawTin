import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'auth_provider.dart';

/// Real sign-in: Firebase anonymous auth. No login screen; each install gets
/// its own account on first use and keeps it.
///
/// Firebase starts lazily, on the first token request, so offline play never
/// touches it. Any failure becomes [AuthUnavailable] (the service treats that
/// as "sign-in refused" and shows a designed message).
class FirebaseAuthProvider implements AuthTokenProvider {
  FirebaseAuthProvider({FirebaseAuth? auth}) : _injected = auth;

  final FirebaseAuth? _injected;
  FirebaseAuth? _auth;

  @override
  String? get debugUid => (_injected ?? _auth)?.currentUser?.uid;

  Future<FirebaseAuth> _ready() async {
    final existing = _injected ?? _auth;
    if (existing != null) return existing;
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    return _auth = FirebaseAuth.instance;
  }

  @override
  Future<String> idToken({bool forceRefresh = false}) async {
    try {
      final auth = await _ready();
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      final token = await user?.getIdToken(forceRefresh);
      if (token == null || token.isEmpty) {
        throw const AuthUnavailable('Sign-in did not return a token.');
      }
      return token;
    } on AuthUnavailable {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthUnavailable('Sign-in failed (${e.code}).');
    } catch (e) {
      throw AuthUnavailable('Sign-in failed: $e');
    }
  }
}
