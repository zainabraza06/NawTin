import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/engine/engine.dart';
import '../../theme/tokens.dart';
import '../../widgets/board_view.dart';
import '../../widgets/call_banner.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/shimmer_box.dart';
import 'demo_scripts.dart';

/// Plays a [DemoScript] in a loop on the real [BoardView], with the same
/// animations and banners as a live game. Runs only while [active].
class DemoPlayer extends StatefulWidget {
  const DemoPlayer({super.key, required this.script, required this.active, this.prefs = const MotionPrefs()});

  final DemoScript script;
  final bool active;
  final MotionPrefs prefs;

  @override
  State<DemoPlayer> createState() => _DemoPlayerState();
}

class _DemoPlayerState extends State<DemoPlayer> {
  late GameState _game;
  MoveResult? _last;
  int _fxSerial = 0;
  int _phutasSerial = 0;
  int _phutasLines = 0;
  int _captureMask = 0;
  Move? _pending;
  int _index = 0;
  List<BannerItem> _banners = const [];
  int _bannerSerial = 0;
  bool _ready = false;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _game = widget.script.start;
    // brief skeleton so the card never pops in half-drawn
    _later(const Duration(milliseconds: 260), () {
      setState(() => _ready = true);
      if (widget.active) _schedule(const Duration(milliseconds: 500));
    });
  }

  @override
  void didUpdateWidget(DemoPlayer old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active && _ready) {
      if (widget.active) {
        _reset();
        _schedule(const Duration(milliseconds: 400));
      } else {
        _cancel();
        _reset();
      }
    }
  }

  void _later(Duration d, VoidCallback f) {
    late final Timer t;
    t = Timer(d, () {
      _timers.remove(t);
      if (mounted) f();
    });
    _timers.add(t);
  }

  void _cancel() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _reset() {
    setState(() {
      _game = widget.script.start;
      _last = null;
      _index = 0;
      _pending = null;
      _captureMask = 0;
      _phutasLines = 0;
      _banners = const [];
    });
  }

  void _schedule(Duration d) => _later(d, _step);

  void _step() {
    if (!widget.active) return;
    final steps = widget.script.steps;
    if (steps.isEmpty) return;
    if (_index >= steps.length) {
      _later(const Duration(milliseconds: 1800), () {
        _reset();
        _schedule(const Duration(milliseconds: 500));
      });
      return;
    }
    final s = steps[_index];
    if (s.pick) {
      setState(() {
        _pending = s.move.step;
        _captureMask = Rules.captureTargets(_game, s.move.step);
      });
      _later(const Duration(milliseconds: 1400), () => _commit(s));
    } else {
      _commit(s);
    }
  }

  void _commit(DemoStep s) {
    final r = MoveResult.resolve(_game, s.move);
    final items = bannersFor(r);
    setState(() {
      _game = r.after;
      _last = r;
      _fxSerial++;
      _pending = null;
      _captureMask = 0;
      if (items.isNotEmpty) {
        _banners = items;
        _bannerSerial++;
      }
    });
    if (s.phutas && r.canPhutas) {
      _later(const Duration(milliseconds: 1000), () {
        setState(() {
          _phutasLines = r.phutasLines;
          _phutasSerial++;
          _banners = const [phutasBanner];
          _bannerSerial++;
        });
      });
    }
  }

  void _onFxDone(int serial) {
    if (serial != _fxSerial) return;
    _index++;
    // leave room for the Phutas beat after the move that sets it up
    final wait = widget.script.steps[_index - 1].phutas
        ? const Duration(milliseconds: 2600)
        : const Duration(milliseconds: 750);
    _schedule(wait);
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return AspectRatio(
      aspectRatio: 1,
      child: GlassPanel(
        padding: const EdgeInsets.all(6),
        child: !_ready
            ? const ShimmerBox()
            : Stack(
                fit: StackFit.expand,
                children: [
                  BoardView(
                    game: _game,
                    selected: null,
                    targets: 0,
                    captureMask: _captureMask,
                    pending: _pending,
                    lastResult: _last,
                    fxSerial: _fxSerial,
                    phutasLines: _phutasLines,
                    phutasSerial: _phutasSerial,
                    prefs: widget.prefs,
                    onPointTap: (_) {},
                    onFxDone: _onFxDone,
                    semanticsLabel: 'Animated demo board',
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tk.radiusM),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 360,
                        height: 360,
                        child: CallBannerOverlay(items: _banners, serial: _bannerSerial),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
