import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'clock.dart';

/// A verified player identity. Only [uid] is ever stored.
class AuthUser {
  const AuthUser(this.uid, {this.anonymous = true});
  final String uid;
  final bool anonymous;
}

abstract class TokenVerifier {
  /// Returns the user for a valid token, or null.
  Future<AuthUser?> verify(String token);
}

/// LOCAL TESTING ONLY. Accepts `test:<uid>` as a token. `ServerConfig.fromEnv`
/// refuses to enable it on Cloud Run, and it is off unless NAWTIN_TEST_AUTH=1.
class TestTokenVerifier implements TokenVerifier {
  static final _uid = RegExp(r'^[A-Za-z0-9_-]{3,40}$');

  @override
  Future<AuthUser?> verify(String token) async {
    if (!token.startsWith('test:')) return null;
    final uid = token.substring(5);
    return _uid.hasMatch(uid) ? AuthUser(uid) : null;
  }
}

/// Verifies Firebase ID tokens (anonymous or signed in): RS256 signature
/// against Google's rotating public certificates, `aud` = project id,
/// `iss` = https://securetoken.google.com/<project>, not expired, `sub` set.
class FirebaseTokenVerifier implements TokenVerifier {
  FirebaseTokenVerifier(
    this.projectId, {
    http.Client? client,
    this.clock = const SystemClock(),
    Future<Map<String, String>> Function()? fetchCerts,
  })  : _client = client ?? http.Client(),
        _fetchOverride = fetchCerts;

  final String projectId;
  final ServerClock clock;
  final http.Client _client;
  final Future<Map<String, String>> Function()? _fetchOverride;

  static final Uri certsUri = Uri.parse(
    'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
  );

  Map<String, String> _certs = {};
  DateTime _certsUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<Map<String, String>> _keys() async {
    if (clock.now().isBefore(_certsUntil) && _certs.isNotEmpty) return _certs;
    if (_fetchOverride != null) {
      _certs = await _fetchOverride();
      _certsUntil = clock.now().add(const Duration(hours: 1));
      return _certs;
    }
    final res = await _client.get(certsUri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) throw StateError('cert fetch ${res.statusCode}');
    _certs = (jsonDecode(res.body) as Map).map((k, v) => MapEntry(k as String, v as String));
    // honour Cache-Control: max-age, otherwise one hour
    final age = RegExp(r'max-age=(\d+)').firstMatch(res.headers['cache-control'] ?? '');
    _certsUntil = clock.now().add(Duration(seconds: int.tryParse(age?.group(1) ?? '') ?? 3600));
    return _certs;
  }

  /// Fetches Google's signing keys once, at startup, so a broken image
  /// (no CA certificates, no outbound network) shows up in the deploy logs
  /// instead of at the first player's sign-in. Returns the number of keys.
  Future<int> warmUp() async => (await _keys()).length;

  @override
  Future<AuthUser?> verify(String token) async {
    try {
      final unverified = JWT.decode(token);
      final kid = unverified.header?['kid'];
      if (kid is! String) return null;
      var pem = (await _keys())[kid];
      if (pem == null) {
        _certsUntil = DateTime.fromMillisecondsSinceEpoch(0); // key rotated: refetch once
        pem = (await _keys())[kid];
        if (pem == null) return null;
      }
      final jwt = JWT.verify(
        token,
        RSAPublicKey.cert(pem),
        issuer: 'https://securetoken.google.com/$projectId',
        audience: Audience.one(projectId),
      );
      final payload = jwt.payload as Map;
      final sub = payload['sub'];
      if (sub is! String || sub.isEmpty || sub.length > 128) return null;
      final provider = (payload['firebase'] as Map?)?['sign_in_provider'];
      return AuthUser(sub, anonymous: provider == 'anonymous');
    } catch (_) {
      return null; // bad signature, expired, wrong audience, malformed...
    }
  }
}
