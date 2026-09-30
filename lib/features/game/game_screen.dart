import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_router.dart';
import '../../core/engine/engine.dart';
import '../../services/ads/ads_service.dart';
import '../../services/settings.dart';
import '../../services/sound/sound_service.dart';
import '../../services/turn_clock.dart';
import '../setup/game_setup.dart';
import '../../theme/tokens.dart';
import '../../widgets/action_dock.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/board_fx.dart';
import '../../widgets/board_view.dart';
import '../../widgets/call_banner.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/player_card.dart';
import '../../widgets/timer_ring.dart';
import 'ad_gate_sheet.dart';
import 'announcements.dart';
import 'game_controller.dart';
import 'game_over_overlay.dart';
import 'pause_overlay.dart';
import '../../services/haptics.dart';

/// Portrait game screen: opponent zone (~14%), board zone (~58%) and the
/// player zone with the action dock (~28%). Two-player mode for now.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, this.prefsOverride});

  /// Tests pass fixed prefs; the app reads them from settings.
  final MotionPrefs? prefsOverride;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // 1 = board tilted ~8 degrees in perspective, 0 = flat (while interacting)
  late final AnimationController _tilt = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: (widget.prefsOverride?.reduceMotion ?? false) ? 0 : 1,
  );
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _flash =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _swipe =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  MotionPrefs get prefs => widget.prefsOverride ?? ref.read(settingsProvider).motion;

  Timer? _retilt;
  final List<Timer> _later = [];

  void _sfx(Sfx s) => ref.read(soundServiceProvider).play(s);

  /// Spoken by screen readers (TalkBack / VoiceOver); ignored otherwise.
  void _say(String text) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(View.of(context), text, TextDirection.ltr);
  }

  /// Plays [s] after [seconds] (so it lines up with the animation beat).
  void _sfxAt(double seconds, Sfx s) {
    final t = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      if (mounted) _sfx(s);
    });
    _later.add(t);
  }
  List<BannerItem> _banners = const [];
  int _bannerSerial = 0;
  Color _flashColor = Colors.white;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Against the AI the clock waits while the app is in the background; in
  /// two-player it keeps running (otherwise it could be abused).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    ref.read(gameControllerProvider.notifier).setBackgrounded(away);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retilt?.cancel();
    for (final t in _later) {
      t.cancel();
    }
    _tilt.dispose();
    _shake.dispose();
    _flash.dispose();
    _swipe.dispose();
    super.dispose();
  }

  void _flatten() {
    if (prefs.reduceMotion) return;
    _tilt.reverse();
    _retilt?.cancel();
    _retilt = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) _tilt.forward();
    });
  }

  void _onState(GameUiState? prev, GameUiState next) {
    final tk = context.tokens;
    if (prev == null) return;

    if (next.fxSerial != prev.fxSerial && next.lastResult != null) {
      final r = next.lastResult!;
      final items = bannersFor(r);
      if (items.isNotEmpty) {
        setState(() {
          _banners = items;
          _bannerSerial++;
        });
      }
      _say(announceMove(r, next.names));
      final tl = FxTimeline(r);
      r.move.isPlacement ? _sfxAt(tl.moveEnd * 0.68, Sfx.place) : _sfxAt(0, Sfx.move);
      final announced = r.announcedSwing;
      if (announced != null) {
        _sfxAt(tl.waveStart + 0.25, announced.call == Call.treghi ? Sfx.treghi : Sfx.begi);
      }
      final swing = r.announcedSwing;
      if (swing != null && !prefs.reduceMotion) {
        _flashColor = swing.call == Call.treghi ? tk.goldGlow : tk.violet;
        _flash.forward(from: 0);
        swing.call == Call.treghi ? Haptics.heavy() : Haptics.medium();
      }
    }
    if (next.phutasSerial != prev.phutasSerial) {
      _sfx(Sfx.phutas);
      setState(() {
        _banners = const [phutasBanner];
        _bannerSerial++;
      });
      Haptics.tick();
    }
    if (next.game.turn != prev.game.turn && !prefs.reduceMotion) {
      _swipe.forward(from: 0);
    }
    if (next.timeoutSerial != prev.timeoutSerial) _announceTimeout(next);
    if (next.hintText != null && next.hintText != prev.hintText) _say(next.hintText!);
    if (prev.status != GameStatus.gameOver && next.status == GameStatus.gameOver) _gameOverSound(next);
  }

  /// Fanfare for the winner (or either player in two-player), a sad run for a
  /// loss against the AI, a neutral pair for a draw.
  void _gameOverSound(GameUiState ui) {
    final result = ui.game.result;
    if (result == null) return;
    final ai = ref.read(setupProvider).aiSeat;
    final Sfx s;
    if (result.isDraw) {
      s = Sfx.draw;
    } else if (ai != null && result.winner == ai) {
      s = Sfx.lose;
    } else {
      s = Sfx.win;
    }
    _sfxAt(0.7, s);
  }

  void _announceTimeout(GameUiState ui) {
    final tk = context.tokens;
    final name = ui.names[ui.timeoutSeat];
    final you = name == 'You';
    final String msg;
    if (ui.timeoutDisqualified) {
      msg = you
          ? 'Out of time again. You are disqualified.'
          : '$name ran out of time twice and is disqualified.';
    } else {
      msg = you
          ? 'Time is up! A move was played for you. One more timeout and you lose.'
          : '$name ran out of time. A move was played for them. One more timeout and they lose.';
    }
    Haptics.heavy();
    _sfx(Sfx.warning);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tk.amber,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tk.radiusM)),
        content: Text(msg, style: tk.heading(NawTinTokens.scaleXS + 1, color: tk.ink)),
      ));
  }

  int _lastSecond = -1;

  /// Warning at 30s, then a strong haptic tick every second in the last 10s.
  void _onClock(ClockState? prev, ClockState next) {
    if (!next.running) return;
    final sec = next.secondsLeft;
    if (sec == _lastSecond) return;
    _lastSecond = sec;
    if (sec == 30) {
      Haptics.medium();
      _sfx(Sfx.warning);
    }
    if (sec <= 10 && sec > 0) {
      Haptics.heavy();
      _sfx(Sfx.tick);
    }
  }

  void _onImpact(MoveResult r) {
    _sfx(Sfx.machyas);
    Haptics.heavy();
    if (!prefs.reduceMotion) _shake.forward(from: 0);
  }

  void _goHome() =>
      Navigator.of(context).popUntil((r) => r.settings.name == Routes.home || r.isFirst);

  Future<void> _hint() async {
    final ctl = ref.read(gameControllerProvider.notifier);
    final level = await showHintChooser(context);
    if (level == null || !mounted) return;
    final best = level == 2;
    final granted = await showAdGate(
      context,
      title: best ? 'Watch 2 ads to see the best move?' : 'Watch 1 ad to see a warning?',
      body: best
          ? 'You get a warning about the position and the best move, highlighted on the board.'
          : 'You get a warning about what your opponent is up to. It will not show the move.',
      ads: best ? AdCosts.hintBestMove : AdCosts.hintWarning,
      icon: Icons.lightbulb_rounded,
      run: (onStart, onProgress) =>
          ctl.watchAds(best ? AdCosts.hintBestMove : AdCosts.hintWarning, onStart: onStart, onProgress: onProgress),
    );
    if (!granted || !mounted) return;
    best ? await ctl.applyBestMoveHint() : ctl.applyWarningHint();
  }

  Future<void> _rewind() async {
    final ctl = ref.read(gameControllerProvider.notifier);
    final granted = await showAdGate(
      context,
      title: 'Watch 3 ads to rewind?',
      body: 'Undo your last move and the reply. Captured tokens come back and your clock restarts.',
      ads: AdCosts.rewind,
      icon: Icons.replay_rounded,
      run: (onStart, onProgress) =>
          ctl.watchAds(AdCosts.rewind, onStart: onStart, onProgress: onProgress),
    );
    if (!granted || !mounted) return;
    ctl.rewind();
  }

  void _pressPause() {
    final ctl = ref.read(gameControllerProvider.notifier);
    if (ctl.pause()) return;
    final ui = ref.read(gameControllerProvider);
    final tk = context.tokens;
    final msg = ui.pausesUsed >= GameController.maxPauses
        ? 'No pauses left in this game.'
        : 'You can pause once it is your turn to move.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: tk.bgBottom,
        content: Text(msg, style: tk.body(NawTinTokens.scaleXS + 1, color: tk.textPrimary)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider); // rebuild when motion prefs change
    ref.listen<GameUiState>(gameControllerProvider, _onState);
    ref.listen<ClockState>(clockProvider, _onClock);
    final ui = ref.watch(gameControllerProvider);
    final ctl = ref.read(gameControllerProvider.notifier);
    final tk = context.tokens;

    return Scaffold(
      body: AuroraBackground(
        prefs: prefs,
        child: AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final v = _shake.value;
            final amp = prefs.reduceMotion ? 0.0 : 9.0 * (1 - v);
            return Transform.translate(
              offset: Offset(math.sin(v * 46) * amp, math.cos(v * 39) * amp * 0.7),
              child: child,
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final h = box.maxHeight;
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: tk.space2),
                          child: Column(
                            children: [
                              SizedBox(height: h * 0.14, child: _TopZone(ui: ui, onPause: _pressPause, seat: 1 - _bottomSeat(ref.watch(setupProvider)))),
                              SizedBox(
                                height: h * 0.58,
                                child: _BoardZone(ui: ui, ctl: ctl, tilt: _tilt, onTouch: _flatten, onImpact: _onImpact, prefs: prefs),
                              ),
                              SizedBox(height: h * 0.28, child: _BottomZone(
                                  ui: ui,
                                  ctl: ctl,
                                  seat: _bottomSeat(ref.watch(setupProvider)),
                                  vsAi: ref.watch(setupProvider).mode == GameMode.vsAi,
                                  onHint: ctl.canAssist ? _hint : null,
                                  onRewind: ctl.canRewind ? _rewind : null,
                                )),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              CallBannerOverlay(items: _banners, serial: _bannerSerial),
              // stronger screen pulse for begi / treghi
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flash,
                  builder: (context, _) => ColoredBox(
                    color: _flashColor.withValues(alpha: 0.28 * math.sin(_flash.value * math.pi)),
                  ),
                ),
              ),
              // soft swipe of light between the two player cards
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _swipe,
                  builder: (context, _) => CustomPaint(
                    painter: _SwipePainter(_swipe.value, ui.game.turn == 0, tk.textPrimary),
                  ),
                ),
              ),
              if (ui.paused)
                PausedOverlay(
                  pausesLeft: GameController.maxPauses - ui.pausesUsed,
                  onResume: ctl.resume,
                  onRestart: () {
                    ctl.resume();
                    ctl.newGame();
                  },
                  onQuit: _goHome,
                ),
              if (ui.status == GameStatus.gameOver)
                GameOverOverlay(
                  ui: ui,
                  prefs: prefs,
                  onRematch: ctl.rematch,
                  onChangeMode: () => Navigator.of(context).maybePop(),
                  onHome: _goHome,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipePainter extends CustomPainter {
  _SwipePainter(this.t, this.downward, this.color);
  final double t;
  final bool downward;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final k = Curves.easeInOut.transform(t);
    final y = (downward ? k : 1 - k) * size.height;
    final band = size.height * 0.12;
    final rect = Rect.fromLTWH(0, y - band / 2, size.width, band);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.13 * math.sin(t * math.pi)),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SwipePainter old) => old.t != t;
}

/// Seat shown at the bottom of the screen: the human (vs AI) or seat 0.
int _bottomSeat(GameSetup setup) {
  final ai = setup.aiSeat;
  return ai == null ? 0 : 1 - ai;
}

PlayerCard _cardFor(GameUiState ui, int seat) {
  final g = ui.game;
  return PlayerCard(
    seat: seat,
    name: ui.names[seat],
    toPlace: g.handOf(seat),
    onBoard: popCount(g.maskOf(seat)),
    eaten: ui.eaten[seat],
    active: g.turn == seat && !g.isOver,
  );
}

// ------------------------------------------------------------------ zones

class _TopZone extends ConsumerWidget {
  const _TopZone({required this.ui, required this.onPause, required this.seat});
  final GameUiState ui;
  final VoidCallback onPause;

  /// The opponent's seat (shown at the top).
  final int seat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final g = ui.game;
    final clock = ref.watch(clockProvider);
    final pausesLeft = GameController.maxPauses - ui.pausesUsed;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width, 640) - tk.space2 * 2,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _cardFor(ui, seat)),
            SizedBox(width: tk.space1),
            Opacity(
              opacity: clock.running || g.isOver ? 1 : 0.6,
              child: TimerRing(
                progress: clock.progress,
                secondsLeft: clock.secondsLeft,
              ),
            ),
            Semantics(
              button: true,
              label: 'Pause, $pausesLeft left',
              child: InkResponse(
                onTap: onPause,
                radius: 28,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.pause_rounded, color: pausesLeft > 0 ? tk.textMuted : tk.textMuted.withValues(alpha: 0.35)),
                      Positioned(
                        right: 4,
                        top: 6,
                        child: Text('$pausesLeft', style: tk.digits(NawTinTokens.scaleXS - 2, color: tk.textMuted)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardZone extends StatelessWidget {
  const _BoardZone({
    required this.ui,
    required this.ctl,
    required this.tilt,
    required this.onTouch,
    required this.onImpact,
    required this.prefs,
  });

  final GameUiState ui;
  final GameController ctl;
  final Animation<double> tilt;
  final VoidCallback onTouch;
  final ValueChanged<MoveResult> onImpact;
  final MotionPrefs prefs;

  String get _caption {
    final g = ui.game;
    final name = ui.names[g.turn];
    switch (ui.status) {
      case GameStatus.gameOver:
        return 'Game over';
      case GameStatus.capturePick:
        return 'Machyas! Tap a glowing opponent token to eat it.';
      case GameStatus.aiThinking:
        return '$name is thinking...';
      case GameStatus.autoPlaying:
        return 'Time is up. Playing a move for $name...';
      case GameStatus.animating:
      case GameStatus.awaitingInput:
        if (g.handOf(g.turn) > 0) {
          final two = g.placesLeft > 1 ? ' You place two tokens this turn.' : '';
          return '$name: place a token on any point.$two';
        }
        return ui.selected == null
            ? '$name: tap one of your tokens to move it.'
            : '$name: tap a glowing point to slide there.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final g = ui.game;
    final chip = switch (ui.status) {
      GameStatus.capturePick => 'EAT A TOKEN',
      GameStatus.aiThinking => 'THINKING',
      GameStatus.autoPlaying => 'AUTO-PLAY',
      _ => g.phase == GamePhase.placement ? 'PLACEMENT' : 'MOVEMENT',
    };
    final chipColor = switch (ui.status) {
      GameStatus.capturePick => tk.danger,
      GameStatus.aiThinking => tk.aqua,
      GameStatus.autoPlaying => tk.amber,
      _ => tk.violet,
    };

    // a slow camera-style zoom towards the last move when the game ends
    final last = ui.lastResult?.move.to;
    final zoomAt = last == null
        ? Alignment.center
        : Alignment(Board.gridOf(last)[0] / 3 - 1, Board.gridOf(last)[1] / 3 - 1);

    return Column(
      children: [
        SizedBox(
          height: 34,
          child: AnimatedSwitcher(
            duration: tk.medium,
            switchInCurve: tk.emphasized,
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween(begin: const Offset(0.5, 0), end: Offset.zero).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Container(
              key: ValueKey(chip),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tk.radiusL),
                color: chipColor.withValues(alpha: 0.22),
                border: Border.all(color: chipColor.withValues(alpha: 0.6)),
              ),
              child: Text(chip, style: tk.heading(NawTinTokens.scaleXS).copyWith(letterSpacing: 1.6)),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final side = math.min(box.maxWidth, box.maxHeight - 8);
              return Center(
                child: AnimatedBuilder(
                  animation: tilt,
                  builder: (context, child) => Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateX(-8 * math.pi / 180 * tilt.value),
                    child: child,
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: ui.isOver ? 1.1 : 1.0),
                    duration: ui.isOver ? const Duration(milliseconds: 2200) : tk.medium,
                    curve: Curves.easeInOutCubic,
                    builder: (context, z, child) =>
                        Transform.scale(scale: z, alignment: zoomAt, child: child),
                    child: SizedBox.square(
                      dimension: side,
                      child: GlassPanel(
                        padding: const EdgeInsets.all(6),
                        child: BoardView(
                          game: g,
                          selected: ui.selected,
                          targets: ui.targets,
                          captureMask: ui.captureMask,
                          pending: ui.pendingStep,
                          hint: ui.hintMove,
                          lastResult: ui.lastResult,
                          fxSerial: ui.fxSerial,
                          phutasLines: ui.phutasLines,
                          phutasSerial: ui.phutasSerial,
                          prefs: prefs,
                          onPointTap: (p) {
                            onTouch();
                            ctl.tapPoint(p);
                          },
                          onFxDone: ctl.finishAnimation,
                          onImpact: onImpact,
                          seatNames: ui.names,
                          semanticsLabel:
                              'Naw Tin board. ${ui.names[g.turn]} to play. $_caption',
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 68,
          child: Center(
            child: AnimatedSwitcher(
              duration: tk.medium,
              child: ui.hintText != null
                  ? GestureDetector(
                      key: const ValueKey('hint'),
                      onTap: ctl.clearHint,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(tk.radiusM),
                          color: tk.lime.withValues(alpha: 0.12),
                          border: Border.all(color: tk.lime.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_rounded, color: tk.lime, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ui.hintText!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: tk.body(NawTinTokens.scaleXS - 0.5, color: tk.textPrimary),
                              ),
                            ),
                            Icon(Icons.close_rounded, color: tk.textMuted, size: 18),
                          ],
                        ),
                      ),
                    )
                  : Text(
                      _caption,
                      key: ValueKey(_caption),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: tk.body(NawTinTokens.scaleXS, color: tk.textPrimary.withValues(alpha: 0.85)),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomZone extends StatelessWidget {
  const _BottomZone({
    required this.ui,
    required this.ctl,
    required this.seat,
    required this.vsAi,
    required this.onHint,
    required this.onRewind,
  });
  final GameUiState ui;
  final GameController ctl;
  final bool vsAi;
  final VoidCallback? onHint;
  final VoidCallback? onRewind;

  /// The seat shown at the bottom (the human player).
  final int seat;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width, 640) - tk.space2 * 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cardFor(ui, seat),
            SizedBox(height: tk.space2),
            ActionDock(
              phutasReady: ui.phutasReady && ui.status != GameStatus.gameOver,
              onPhutas: ctl.callPhutas,
              showAssist: vsAi,
              onHint: onHint,
              onRewind: onRewind,
            ),
          ],
        ),
      ),
    );
  }
}
