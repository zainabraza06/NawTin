import 'package:flutter/foundation.dart';

/// Where the online server lives, and the safety rules around it.
///
/// * Release builds accept **`wss://` only**. A plain `ws://` address is refused,
///   and so is a missing one (online play is then reported as unavailable).
/// * Debug builds also allow `ws://` for a server on your own machine.
///
/// Set the address with `--dart-define=NAWTIN_SERVER=wss://example.run.app/ws`.
/// For a debug build without it, the default is the host machine: the Android
/// emulator reaches it at `10.0.2.2`, everything else at `localhost`. (A physical
/// phone over USB: `adb reverse tcp:8080 tcp:8080`, then `ws://localhost:8080/ws`.)
class OnlineConfig {
  const OnlineConfig._(this.url, this.problem);

  /// The server address, or null when online play cannot be used.
  final Uri? url;

  /// Why [url] is null (shown to the developer, never raw to players).
  final String? problem;

  bool get isAvailable => url != null;

  static const String _define = String.fromEnvironment('NAWTIN_SERVER');

  /// Resolves the address from the build settings.
  factory OnlineConfig.fromEnvironment({
    bool release = kReleaseMode,
    String? override,
    TargetPlatform? platform,
    bool web = kIsWeb,
  }) {
    final raw = (override != null && override.isNotEmpty) ? override : _define;
    if (raw.isNotEmpty) return OnlineConfig.parse(raw, release: release);
    if (release) {
      return const OnlineConfig._(null, 'No server address was set for this release build.');
    }
    final host = (!web && (platform ?? defaultTargetPlatform) == TargetPlatform.android) ? '10.0.2.2' : 'localhost';
    return OnlineConfig._(Uri.parse('ws://$host:8080/ws'), null);
  }

  /// Validates [raw]; the result is unavailable (with a reason) if it is unsafe.
  factory OnlineConfig.parse(String raw, {required bool release}) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return const OnlineConfig._(null, 'The server address is not a valid URL.');
    }
    switch (uri.scheme) {
      case 'wss':
        return OnlineConfig._(uri, null);
      case 'ws':
        if (release) {
          return const OnlineConfig._(null, 'Release builds only connect over wss:// (encrypted).');
        }
        return OnlineConfig._(uri, null);
      default:
        return const OnlineConfig._(null, 'The server address must start with wss:// (or ws:// in debug builds).');
    }
  }

  @override
  String toString() => url?.toString() ?? 'unavailable ($problem)';
}
