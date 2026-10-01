import 'dart:async';

typedef Cancel = void Function();

/// Time and timers behind one interface so every rule that depends on time
/// (room expiry, turn clock, reconnect window, rate limits) is testable with a
/// [FakeClock] that never sleeps.
abstract class ServerClock {
  DateTime now();

  /// Runs [f] once after [d]. Call the returned function to cancel.
  Cancel after(Duration d, void Function() f);

  /// Runs [f] every [d]. Call the returned function to cancel.
  Cancel every(Duration d, void Function() f);
}

class SystemClock implements ServerClock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Cancel after(Duration d, void Function() f) {
    final t = Timer(d, f);
    return t.cancel;
  }

  @override
  Cancel every(Duration d, void Function() f) {
    final t = Timer.periodic(d, (_) => f());
    return t.cancel;
  }
}

/// Deterministic clock for tests: time moves only when [advance] is called,
/// and due timers fire in order, each seeing the correct `now()`.
class FakeClock implements ServerClock {
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 1, 1);

  DateTime _now;
  final List<_Task> _tasks = [];
  int _order = 0;

  @override
  DateTime now() => _now;

  @override
  Cancel after(Duration d, void Function() f) => _add(d, f, null);

  @override
  Cancel every(Duration d, void Function() f) => _add(d, f, d);

  Cancel _add(Duration d, void Function() f, Duration? period) {
    final t = _Task(_now.add(d), _order++, f, period);
    _tasks.add(t);
    return () => t.cancelled = true;
  }

  int get pendingTimers => _tasks.where((t) => !t.cancelled).length;

  void advance(Duration d) {
    final target = _now.add(d);
    while (true) {
      _tasks.removeWhere((t) => t.cancelled);
      _tasks.sort((a, b) {
        final c = a.due.compareTo(b.due);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
      if (_tasks.isEmpty || _tasks.first.due.isAfter(target)) break;
      final t = _tasks.removeAt(0);
      _now = t.due;
      if (t.period != null) {
        t.due = t.due.add(t.period!);
        t.order = _order++;
        _tasks.add(t);
      }
      t.fn();
    }
    _now = target;
  }
}

class _Task {
  _Task(this.due, this.order, this.fn, this.period);
  DateTime due;
  int order;
  final void Function() fn;
  final Duration? period;
  bool cancelled = false;
}
