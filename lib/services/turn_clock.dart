import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class ClockState {
  const ClockState({required this.totalMs, required this.remainingMs, required this.running});

  final int totalMs;
  final int remainingMs;

  /// Whether time is currently draining.
  final bool running;

  int get secondsLeft => (remainingMs / 1000).ceil();
  double get progress => totalMs == 0 ? 0 : remainingMs / totalMs;
  bool get expired => remainingMs <= 0;

  /// Below 30s the ring turns amber; the last 10s are the strong warning.
  bool get warning => secondsLeft <= 30;
  bool get urgent => secondsLeft <= 10;

  ClockState copyWith({int? totalMs, int? remainingMs, bool? running}) => ClockState(
        totalMs: totalMs ?? this.totalMs,
        remainingMs: remainingMs ?? this.remainingMs,
        running: running ?? this.running,
      );
}

/// The per-turn countdown. It only drains while [ClockState.running]; the game
/// controller decides when that is (never during animations, AI thinking,
/// ads, pauses, or while the app is in the background against the AI).
///
/// [advance] holds the whole rule ("drain by dt, expire at zero") so tests can
/// step time without real timers.
class ClockController extends Notifier<ClockState> {
  Timer? _ticker;
  DateTime _last = DateTime.now();

  /// Called once when the countdown reaches zero.
  VoidCallback? onExpired;

  static const Duration _tick = Duration(milliseconds: 200);

  @override
  ClockState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const ClockState(totalMs: 120000, remainingMs: 120000, running: false);
  }

  /// New turn: full time, not running until [setRunning] says so.
  void reset(int totalMs) {
    state = ClockState(totalMs: totalMs, remainingMs: totalMs, running: state.running);
  }

  /// Restores the full countdown (used by rewind).
  void refill() => state = state.copyWith(remainingMs: state.totalMs);

  void setRunning(bool run) {
    if (run == state.running) return;
    if (run && state.expired) return;
    state = state.copyWith(running: run);
    if (run) {
      _last = DateTime.now();
      _ticker ??= Timer.periodic(_tick, (_) {
        final now = DateTime.now();
        // never less than one nominal tick; more if the timer was delayed
        // (a stall) or the phone slept while the clock had to keep running
        advance(math.max(_tick.inMilliseconds, now.difference(_last).inMilliseconds));
        _last = now;
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Drains [ms] if running; fires [onExpired] when it hits zero.
  void advance(int ms) {
    if (!state.running || ms <= 0) return;
    final left = state.remainingMs - ms;
    if (left > 0) {
      state = state.copyWith(remainingMs: left);
      return;
    }
    state = state.copyWith(remainingMs: 0, running: false);
    _ticker?.cancel();
    _ticker = null;
    onExpired?.call();
  }
}

final clockProvider = NotifierProvider<ClockController, ClockState>(ClockController.new);
