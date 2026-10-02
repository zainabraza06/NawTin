import 'dart:async';
import 'dart:io';

import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart';

Future<void> main() async {
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnv(Platform.environment);
  } on StateError catch (e) {
    stderr.writeln('FATAL: ${e.message}');
    exit(78); // configuration error
  }

  // Both players open with two tokens, exactly as in the app.
  Rules.placementRule = PlacementRule.symmetricOpening;

  final TokenVerifier verifier;
  if (config.testAuth) {
    stderr.writeln('*' * 72);
    stderr.writeln('* WARNING: NAWTIN_TEST_AUTH=1 - fake "test:<uid>" tokens are ACCEPTED.');
    stderr.writeln('* Anyone can impersonate anyone. Use for LOCAL development only.');
    stderr.writeln('*' * 72);
    verifier = TestTokenVerifier();
  } else {
    verifier = FirebaseTokenVerifier(config.firebaseProjectId!);
  }

  final server = NawTinServer(config: config, verifier: verifier);
  final http = await server.serve();
  final v = verifier;
  if (v is FirebaseTokenVerifier) {
    // the server keeps running either way; the log line is what to look for
    try {
      final n = await v.warmUp();
      stdout.writeln('auth.certs_ok: fetched $n Google signing keys');
    } catch (e) {
      stderr.writeln('auth.certs_failed: cannot fetch Google signing keys ($e). '
          'Real sign-in will fail until this works (check CA certificates and outbound network).');
    }
  }
  stdout.writeln('Naw Tin server listening on :${http.port} '
      '(protocol $protocolVersion, ${config.testAuth ? "TEST AUTH" : "firebase ${config.firebaseProjectId}"})');

  // Cloud Run stops instances with SIGTERM: close sockets cleanly. Windows
  // only supports SIGINT (Ctrl+C), so ignore signals the platform lacks.
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    // the error arrives on the stream, not from watch(): swallow "unsupported"
    signal.watch().listen(
      (_) async {
        await server.stop();
        exit(0);
      },
      onError: (Object _) {},
    );
  }
}
