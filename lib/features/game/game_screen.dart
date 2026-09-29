import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_router.dart';
import '../../core/engine/engine.dart';
import '../../services/settings.dart';
import '../setup/game_setup.dart';
import '../../theme/tokens.dart';
import '../../widgets/action_dock.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/board_view.dart';
import '../../widgets/call_banner.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/player_card.dart';
import '../../widgets/timer_ring.dart';
import 'game_controller.dart';
import 'game_over_overlay.dart';

/// Portrait game screen: opponent zone (~14%), board zone (~58%) and the
/// player zone with the action dock (~28%). Two-player mode for now.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, this.prefsOverride});

  /// Tests pass fixed prefs; the app reads them from settings.
  final MotionPrefs? prefsOverride;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with TickerProviderStateMixin {
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
  List<BannerItem> _banners = const [];
  int _bannerSerial = 0;
  Color _flashColor = Colors.white;

  @override
  void dispose() {
    _retilt?.cancel();
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
      final swing = r.announcedSwing;
      if (swing != null && !prefs.reduceMotion) {
        _flashColor = swing.call == Call.treghi ? tk.goldGlow : tk.violet;
        _flash.forward(from: 0);
        swing.call == Call.treghi ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
      }
    }
    if (next.phutasSerial != prev.phutasSerial) {
      setState(() {
        _banners = const [phutasBanner];
        _bannerSerial++;
      });
      HapticFeedback.selectionClick();
    }
    if (next.game.turn != prev.game.turn && !prefs.reduceMotion) {
      _swipe.forward(from: 0);
    }
  }

  void _onImpact(MoveResult r) {
    HapticFeedback.heavyImpact();
    if (!prefs.reduceMotion) _shake.forward(from: 0);
  }

  void _goHome() =>
      Navigator.of(context).popUntil((r) => r.settings.name == Routes.home || r.isFirst);

  void _openPause() {
    final tk = context.tokens;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.all(tk.space2),
        child: GlassPanel(
          padding: EdgeInsets.all(tk.space3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Paused', style: tk.heading(NawTinTokens.scaleM)),
              const SizedBox(height: 4),
              Text('Take a breath. The board will wait.', style: tk.body(NawTinTokens.scaleS)),
              SizedBox(height: tk.space2),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: tk.violet),
                onPressed: () => Navigator.pop(ctx),
                child: Text('Resume', style: tk.heading(NawTinTokens.scaleS)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () {
                  Navigator.pop(ctx);
                  ref.read(gameControllerProvider.notifier).newGame();
                },
                child: Text('Restart game', style: tk.heading(NawTinTokens.scaleS, color: tk.textPrimary)),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _goHome();
                },
                child: Text('Quit to home', style: tk.heading(NawTinTokens.scaleS, color: tk.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider); // rebuild when motion prefs change
    ref.listen<GameUiState>(gameControllerProvider, _onState);
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
                              SizedBox(height: h * 0.14, child: _TopZone(ui: ui, onPause: _openPause, seconds: ref.watch(setupProvider).turnSeconds)),
                              SizedBox(
                                height: h * 0.58,
                                child: _BoardZone(ui: ui, ctl: ctl, tilt: _tilt, onTouch: _flatten, onImpact: _onImpact, prefs: prefs),
                              ),
                              SizedBox(height: h * 0.28, child: _BottomZone(ui: ui, ctl: ctl)),
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
              if (ui.status == GameStatus.gameOver)
                GameOverOverlay(
                  ui: ui,
                  prefs: prefs,
                  onRematch: ctl.newGame,
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

// ------------------------------------------------------------------ zones

class _TopZone extends StatelessWidget {
  const _TopZone({required this.ui, required this.onPause, required this.seconds});
  final GameUiState ui;
  final VoidCallback onPause;

  /// Per-turn clock (Stage 5 makes the ring count down).
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final g = ui.game;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width, 640) - tk.space2 * 2,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: PlayerCard(
                seat: 1,
                name: ui.names[1],
                toPlace: g.hand1,
                onBoard: popCount(g.mask1),
                eaten: ui.eaten[1],
                active: g.turn == 1 && !g.isOver,
              ),
            ),
            SizedBox(width: tk.space1),
            // Stage 5 feeds the ring with the live countdown; two-player is 2:00
            TimerRing(progress: 1, secondsLeft: seconds, accent: tk.seatColor(g.turn)),
            IconButton(
              tooltip: 'Pause',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onPause,
              icon: Icon(Icons.pause_rounded, color: tk.textMuted),
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
    final chip = ui.status == GameStatus.capturePick
        ? 'EAT A TOKEN'
        : (g.phase == GamePhase.placement ? 'PLACEMENT' : 'MOVEMENT');
    final chipColor = ui.status == GameStatus.capturePick ? tk.danger : tk.violet;

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
          height: 40,
          child: Center(
            child: AnimatedSwitcher(
              duration: tk.medium,
              child: Text(
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
  const _BottomZone({required this.ui, required this.ctl});
  final GameUiState ui;
  final GameController ctl;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final g = ui.game;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width, 640) - tk.space2 * 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerCard(
              seat: 0,
              name: ui.names[0],
              toPlace: g.hand0,
              onBoard: popCount(g.mask0),
              eaten: ui.eaten[0],
              active: g.turn == 0 && !g.isOver,
            ),
            SizedBox(height: tk.space2),
            ActionDock(
              phutasReady: ui.phutasReady && ui.status != GameStatus.gameOver,
              onPhutas: ctl.callPhutas,
            ),
          ],
        ),
      ),
    );
  }
}
