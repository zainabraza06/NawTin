// Smoke test for a running Naw Tin server (local or Cloud Run).
//
//   dart run tool/check.dart https://naw-tin-server-xxxx-el.a.run.app
//   dart run tool/check.dart http://localhost:8080
//
// It checks, without needing a Firebase account:
//   1. GET /healthz answers "ok"
//   2. the WebSocket at /ws accepts a connection (wss:// for https:// hosts)
//   3. a fake sign-in token is REFUSED with `unauthorized` / close code 4001
//      (so a deployed server is not running in test mode)
//   4. a hello with an unsupported protocol is refused with 4000 (outdated app)
//
// Exit code 0 = all passed. This does not prove real Firebase sign-in works;
// that needs a real app (see docs/two_device_test_plan.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/check.dart <https://host | http://host:port>');
    exit(64);
  }
  final base = Uri.parse(args.first.endsWith('/') ? args.first.substring(0, args.first.length - 1) : args.first);
  final secure = base.scheme == 'https' || base.scheme == 'wss';
  final httpBase = base.replace(scheme: secure ? 'https' : 'http');
  final wsUrl = base.replace(scheme: secure ? 'wss' : 'ws', path: '/ws');
  var failed = 0;

  void report(String name, bool ok, [String detail = '']) {
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : '  ($detail)'}');
    if (!ok) failed++;
  }

  // 1. health
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final r = await (await c.getUrl(httpBase.replace(path: '/healthz'))).close();
    final body = await utf8.decoder.bind(r).join();
    report('/healthz answers ok', r.statusCode == 200 && body.trim() == 'ok', 'HTTP ${r.statusCode}');
    c.close();
  } catch (e) {
    report('/healthz answers ok', false, '$e');
  }

  // 2 + 3. a fake token must be refused
  Future<({String? errorCode, int? closeCode, bool connected})> hello(Map<String, Object?> msg) async {
    String? code;
    var connected = false;
    final ws = await WebSocket.connect(wsUrl.toString()).timeout(const Duration(seconds: 10));
    connected = true;
    final done = Completer<void>();
    ws.listen((raw) {
      final m = jsonDecode(raw as String) as Map;
      if (m['t'] == 'error') code ??= m['code'] as String?;
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    ws.add(jsonEncode(msg));
    await done.future.timeout(const Duration(seconds: 10), onTimeout: () => ws.close());
    return (errorCode: code, closeCode: ws.closeCode, connected: connected);
  }

  try {
    final r = await hello({'v': 1, 't': 'hello', 'protocol': 1, 'token': 'test:intruder1', 'name': 'Intruder'});
    report('WebSocket connects', r.connected);
    report('a fake test token is refused (server is not in test mode)', r.errorCode == 'unauthorized' && r.closeCode == 4001,
        'error ${r.errorCode}, close ${r.closeCode}');
  } catch (e) {
    report('WebSocket connects', false, '$e');
  }

  // 4. an app that is too old
  try {
    final r = await hello({'v': 1, 't': 'hello', 'protocol': 0, 'token': 'x', 'name': 'Old'});
    report('an unsupported protocol gets the "please update" refusal', r.closeCode == 4000 || r.errorCode == 'unsupported_version',
        'error ${r.errorCode}, close ${r.closeCode}');
  } catch (e) {
    report('an unsupported protocol gets the "please update" refusal', false, '$e');
  }

  stdout.writeln(failed == 0 ? '\nAll checks passed.' : '\n$failed check(s) FAILED.');
  exit(failed == 0 ? 0 : 1);
}
