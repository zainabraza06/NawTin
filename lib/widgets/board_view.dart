import 'package:flutter/material.dart';

import '../core/engine/engine.dart';
import '../theme/tokens.dart';
import 'board_fx.dart';
import 'board_painter.dart';
import '../services/haptics.dart';

/// The interactive board. Always square, wrapped in a RepaintBoundary, and
/// driven by three controllers: a looping pulse, the per-move effect timeline
/// and the PHUTAS pulse.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.game,
    required this.selected,
    required this.targets,
    required this.captureMask,
    this.pending,
    this.hint,
    required this.lastResult,
    required this.fxSerial,
    required this.phutasLines,
    required this.phutasSerial,
    required this.onPointTap,
    required this.onFxDone,
    this.onImpact,
    this.prefs = const MotionPrefs(),
    this.semanticsLabel = 'Naw Tin board',
  });

  final GameState game;
  final int? selected;
  final int targets;
  final int captureMask;

  /// A step waiting for its capture choice: drawn in place so the player
  /// sees the token they just placed / moved while choosing what to eat.
  final Move? pending;

  /// Best move to highlight (Hint 2).
  final Move? hint;
  final MoveResult? lastResult;
  final int fxSerial;
  final int phutasLines;
  final int phutasSerial;
  final ValueChanged<int> onPointTap;

  /// Called once the effects for [fxSerial] have finished.
  final ValueChanged<int> onFxDone;

  /// Called when a capture lands (screen shake) with the move result.
  final ValueChanged<MoveResult>? onImpact;
  final MotionPrefs prefs;
  final String semanticsLabel;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  late final AnimationController _fxCtrl = AnimationController(vsync: this);
  late final AnimationController _phutasCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  FxTimeline? _timeline;
  int _handledSerial = 0;
  bool _impactSent = false;

  @override
  void initState() {
    super.initState();
    _handledSerial = widget.fxSerial; // do not replay a move on first build
    _fxCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onFxDone(_handledSerial);
    });
    _fxCtrl.addListener(_checkImpact);
  }

  void _checkImpact() {
    final tl = _timeline;
    if (tl == null || _impactSent || !tl.result.isMachyas) return;
    if (_fxCtrl.value * tl.total >= tl.impactTime) {
      _impactSent = true;
      widget.onImpact?.call(tl.result);
    }
  }

  @override
  void didUpdateWidget(BoardView old) {
    super.didUpdateWidget(old);
    if (widget.fxSerial != _handledSerial && widget.lastResult != null) {
      _handledSerial = widget.fxSerial;
      final tl = FxTimeline(widget.lastResult!);
      _timeline = tl;
      _impactSent = false;
      _fxCtrl.duration = widget.prefs.reduceMotion
          ? const Duration(milliseconds: 250)
          : tl.duration;
      _fxCtrl.forward(from: 0);
      Haptics.light();
    }
    if (widget.phutasSerial != old.phutasSerial && widget.phutasSerial > 0) {
      _phutasCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fxCtrl.dispose();
    _phutasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Semantics(
      label: widget.semanticsLabel,
      container: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final p = BoardPainter.pointAt(d.localPosition, size);
                if (p != null) widget.onPointTap(p);
              },
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _fxCtrl, _phutasCtrl]),
                  builder: (context, _) {
                    final tl = _timeline;
                    final fxRunning = tl != null && _fxCtrl.isAnimating;
                    final phutasT = _phutasCtrl.isAnimating ? _phutasCtrl.value : null;
                    var m0 = widget.game.mask0, m1 = widget.game.mask1;
                    final pend = widget.pending;
                    if (pend != null) {
                      final add = bit(pend.to);
                      final drop = pend.isPlacement ? 0 : bit(pend.from);
                      if (widget.game.turn == 0) {
                        m0 = (m0 & ~drop) | add;
                      } else {
                        m1 = (m1 & ~drop) | add;
                      }
                    }
                    return CustomPaint(
                      size: size,
                      painter: BoardPainter(
                        tk: tk,
                        mask0: m0,
                        mask1: m1,
                        selected: widget.selected,
                        targets: widget.targets,
                        captureMask: widget.captureMask,
                        pickerSeat: widget.game.turn,
                        pulse: _pulse.value,
                        fx: fxRunning ? tl : null,
                        fxSeconds: tl == null ? 0 : _fxCtrl.value * tl.total,
                        phutasLines: widget.phutasLines,
                        phutasT: phutasT,
                        prefs: widget.prefs,
                        hint: widget.hint,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
