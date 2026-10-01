/// Server settings. Everything is overridable from the environment so the same
/// image runs locally, in tests and on Cloud Run.
///
/// | variable | meaning | default |
/// |---|---|---|
/// | `PORT` | listen port (Cloud Run sets it) | `8080` |
/// | `FIREBASE_PROJECT_ID` | project whose ID tokens are accepted | (required unless test auth) |
/// | `NAWTIN_TEST_AUTH` | `1` accepts fake `test:<uid>` tokens (local use only) | off |
/// | `NAWTIN_TURN_SECONDS` | turn clock | `120` |
/// | `NAWTIN_RECONNECT_SECONDS` | reconnect window | `45` |
/// | `NAWTIN_ROOM_MINUTES` | waiting-room lifetime | `10` |
class ServerConfig {
  const ServerConfig({
    this.port = 8080,
    this.firebaseProjectId,
    this.testAuth = false,
    this.turnSeconds = 120,
    this.reconnectSeconds = 45,
    this.roomMinutes = 10,
    this.rematchMinutes = 5,
    this.graceMs = 1500,
    this.helloTimeoutSeconds = 5,
    this.idleTimeoutSeconds = 45,
    this.maxFrameBytes = 4096,
    this.autoMoveMs = 200,
  });

  final int port;

  /// Firebase project id used to verify ID tokens (`aud` / `iss`).
  final String? firebaseProjectId;

  /// Accept fake `test:<uid>` tokens. NEVER on in a deployed server.
  final bool testAuth;

  final int turnSeconds;
  final int reconnectSeconds;
  final int roomMinutes;
  final int rematchMinutes;

  /// Extra time added after each confirmed move so animations never cost the
  /// next player time.
  final int graceMs;

  final int helloTimeoutSeconds;
  final int idleTimeoutSeconds;
  final int maxFrameBytes;

  /// Thinking time for the Easy-strength auto-move on a timeout.
  final int autoMoveMs;

  Duration get turn => Duration(seconds: turnSeconds);
  Duration get reconnect => Duration(seconds: reconnectSeconds);
  Duration get roomLife => Duration(minutes: roomMinutes);
  Duration get rematchLife => Duration(minutes: rematchMinutes);

  /// Reads the environment. Throws [StateError] for unsafe combinations:
  /// fake-token test mode on Cloud Run, or no way to authenticate at all.
  factory ServerConfig.fromEnv(Map<String, String> env) {
    int n(String k, int d) => int.tryParse(env[k] ?? '') ?? d;
    final test = env['NAWTIN_TEST_AUTH'] == '1';
    // Cloud Run sets K_SERVICE (and K_REVISION / K_CONFIGURATION) on every instance.
    final onCloudRun = env.containsKey('K_SERVICE') || env.containsKey('K_REVISION');
    if (test && onCloudRun) {
      throw StateError(
        'Refusing to start: NAWTIN_TEST_AUTH=1 (fake tokens) is set on Cloud Run. '
        'A deployed server must never accept fake tokens.',
      );
    }
    final project = env['FIREBASE_PROJECT_ID'];
    if (!test && (project == null || project.isEmpty)) {
      throw StateError('FIREBASE_PROJECT_ID is required (or NAWTIN_TEST_AUTH=1 for local testing).');
    }
    return ServerConfig(
      port: n('PORT', 8080),
      firebaseProjectId: project,
      testAuth: test,
      turnSeconds: n('NAWTIN_TURN_SECONDS', 120),
      reconnectSeconds: n('NAWTIN_RECONNECT_SECONDS', 45),
      roomMinutes: n('NAWTIN_ROOM_MINUTES', 10),
    );
  }
}
