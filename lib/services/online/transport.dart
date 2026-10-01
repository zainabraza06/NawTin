import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One open connection to the server.
abstract class TransportChannel {
  /// Text frames from the server. Completes when the socket closes.
  Stream<String> get incoming;

  void send(String data);

  Future<void> close([int? code, String? reason]);

  /// The WebSocket close code once closed (4000 = outdated, 4001 = bad token,
  /// 4002 = replaced by another device, 4003 = rate limited).
  int? get closeCode;
}

abstract class Transport {
  /// Opens a connection; throws if it cannot be established.
  Future<TransportChannel> connect(Uri url);
}

/// Real WebSockets (works on Android, iOS, desktop and web).
class WebSocketTransport implements Transport {
  const WebSocketTransport();

  @override
  Future<TransportChannel> connect(Uri url) async {
    final ch = WebSocketChannel.connect(url);
    await ch.ready.timeout(const Duration(seconds: 10));
    return _WsChannel(ch);
  }
}

class _WsChannel implements TransportChannel {
  _WsChannel(this._ch);
  final WebSocketChannel _ch;

  @override
  Stream<String> get incoming => _ch.stream.where((e) => e is String).cast<String>();

  @override
  void send(String data) => _ch.sink.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    try {
      await _ch.sink.close(code ?? 1000, reason);
    } catch (_) {
      // already closed
    }
  }

  @override
  int? get closeCode => _ch.closeCode;
}

/// Time and timers behind one interface so reconnect backoff, heartbeats and
/// the clock offset are testable without waiting.
abstract class Scheduler {
  DateTime now();
  void Function() after(Duration d, void Function() f);
  void Function() every(Duration d, void Function() f);
}

class SystemScheduler implements Scheduler {
  const SystemScheduler();

  @override
  DateTime now() => DateTime.now();

  @override
  void Function() after(Duration d, void Function() f) => Timer(d, f).cancel;

  @override
  void Function() every(Duration d, void Function() f) => Timer.periodic(d, (_) => f()).cancel;
}
