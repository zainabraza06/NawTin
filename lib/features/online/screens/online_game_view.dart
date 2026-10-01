import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

import '../../../services/haptics.dart';
import '../../../services/settings.dart';
import '../../../services/sound/sound_service.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/action_dock.dart';
import '../../../widgets/aurora_background.dart';
import '../../../widgets/board_fx.dart';
import '../../../widgets/board_view.dart';
import '../../../widgets/call_banner.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/glow_text.dart';
import '../../../widgets/naw_button.dart';
import '../../../widgets/player_card.dart';
import '../../../widgets/timer_ring.dart';
import '../../game/announcements.dart';
import '../online_controller.dart';
import '../online_messages.dart';
import '../widgets/emote_widgets.dart';
import '../online_state.dart';

/// The live online game. It reuses the offline game's board, player cards,
/// timer ring, call banners and sounds; what differs is where the state comes
/// from (the server) and the buttons (Leave instead of Pause; no Hint or
/// Rewind online).
class OnlineGameView extends ConsumerStatefulWidget {
  const OnlineGameView({super.key, required this.onLeave});

  /// The confirmed "Leave game" (a forfeit while the game is live).
  final VoidCallback onLeave;

  @override
  ConsumerState<OnlineGameView> createState() => _OnlineGameViewState();
}

class _OnlineGameViewState extends ConsumerState<OnlineGameView> {
  Timer? _tick;
  int? _selected;
  List<BannerItem> _banners = const [];
  int _bannerSerial = 0;
  int _eventsHandled = 0;
  int _lastSecond = -1;
  EmoteView? _bubble;
  Timer? _bubbleTimer;

  void _sfx(Sfx s) => ref.read(soundServiceProvider).play(s);

  @override
  void initState() {
    super.initState();
    // the countdown is derived from the server's deadline: repaint a few times a second
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      _clockSounds();
    });
    _eventsHandled = ref.read(onlineControllerProvider).events.length;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _bubbleTimer?.cancel();
    super.dispose();
  }

  void _say(String text) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(View.of(context), text, TextDirection.ltr);
  }

  void _clockSounds() {
    final s = ref.read(onlineControllerProvider);
    if (!s.myTurn || s.game?.clock == null) {
      _lastSecond = -1;
      return;
    }
    final sec = (ref.read(onlineControllerProvider.notifier).remainingMs() / 1000).ceil();
    if (sec == _lastSecond) return;
    _lastSecond = sec;
    if (sec == 30) {
      Haptics.medium();
      _sfx(Sfx.warning);
    } else if (sec <= 10 && sec > 0) {
      Haptics.heavy();
      _sfx(Sfx.tick);
    }
  }

  List<String> _names(OnlineState s) {
    String of(int seat) {
      for (final p in s.room?.players ?? const <PlayerView>[]) {
        if (p.seat == seat) return p.name;
      }
      return 'Player ${seat + 1}';
    }

    return [of(0), of(1)];
  }

  // ------------------------------------------------------------ reactions

  void _onState(OnlineState? prev, OnlineState next) {
    final tk = context.tokens;
    final names = _names(next);
    if (prev != null && next.fxSerial != prev.fxSerial && next.lastResult != null) {
      final r = next.lastResult!;
      final items = bannersFor(r);
      if (items.isNotEmpty) {
        setState(() {
          _banners = items;
          _bannerSerial++;
        });
      }
      _say(announceMove(r, names));
      final tl = FxTimeline(r);
      if (r.move.isPlacement) {
        Timer(Duration(milliseconds: (tl.moveEnd * 0.68 * 1000).round()), () {
          if (mounted) _sfx(Sfx.place);
        });
      } else {
        _sfx(Sfx.move);
      }
      final swing = r.announcedSwing;
      if (swing != null) {
        Timer(Duration(milliseconds: ((tl.waveStart + 0.25) * 1000).round()), () {
          if (mounted) _sfx(swing.call == Call.treghi ? Sfx.treghi : Sfx.begi);
        });
        swing.call == Call.treghi ? Haptics.heavy() : Haptics.medium();
      }
      if (r.isMachyas) {
        _sfx(Sfx.machyas);
        Haptics.heavy();
      }
    }
    // an emote from either player (unless emotes are hidden)
    final em = next.lastEmote;
    if (em != null && em.serial != prev?.lastEmote?.serial && !ref.read(hideEmotesProvider)) {
      setState(() => _bubble = em);
      _bubbleTimer?.cancel();
      _bubbleTimer = Timer(const Duration(milliseconds: 2800), () {
        if (mounted) setState(() => _bubble = null);
      });
      if (em.seat != next.mySeat) Haptics.light();
    }
    // a refused action: say why, in words
    final err = next.error;
    if (err != null && err != prev?.error && err.code != ErrorCodes.seqGap) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(errorText(err)),
        ));
    }
    // turn changed to me: nudge
    if (prev != null && !prev.myTurn && next.myTurn) Haptics.light();
    _selected = next.myTurn ? _selected : null;

    // events not handled yet (timeouts, game over)
    final events = next.events;
    if (events.length < _eventsHandled) _eventsHandled = 0;
    for (var i = _eventsHandled; i < events.length; i++) {
      final e = events[i];
      switch (e.kind) {
        case EventKind.timeout:
          final mine = e.seat == next.mySeat;
          final name = names[e.seat ?? 0];
          final dq = e.data['disqualified'] == true;
          _sfx(Sfx.warning);
          Haptics.heavy();
          final msg = dq
              ? (mine ? 'Out of time twice in a row. You lose.' : '$name ran out of time twice in a row and loses.')
              : (mine
                  ? 'Time is up! A move was played for you. One more timeout in a row and you lose.'
                  : '$name ran out of time. A move was played for them.');
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: tk.amber,
              duration: const Duration(seconds: 4),
              content: Text(msg, style: tk.heading(NawTinTokens.scaleXS + 1, color: tk.ink)),
            ));
        case EventKind.phutasPressed:
          _sfx(Sfx.phutas);
          setState(() {
            _banners = const [phutasBanner];
            _bannerSerial++;
          });
        case EventKind.gameOver:
          final w = next.game?.state.result?.winner;
          _sfxAfter(0.7, w == null ? Sfx.draw : (w == next.mySeat ? Sfx.win : Sfx.lose));
      }
    }
    _eventsHandled = events.length;
  }

  void _sfxAfter(double seconds, Sfx s) => Timer(Duration(milliseconds: (seconds * 1000).round()), () {
        if (mounted) _sfx(s);
      });

  // ----------------------------------------------------------------- taps

  void _tap(int p, OnlineState s) {
    final ctl = ref.read(onlineControllerProvider.notifier);
    final g = s.game;
    if (g == null || !s.myTurn || !s.conn.isOnline) return;
    if (g.pendingStep != null) {
      if (g.pendingTargets & bit(p) != 0) {
        Haptics.medium();
        ctl.capture(p);
      }
      return;
    }
    final st = g.state;
    if (st.handOf(st.turn) > 0) {
      ctl.place(p);
      return;
    }
    final mine = st.maskOf(st.turn);
    if (mine & bit(p) != 0) {
      Haptics.light();
      setState(() => _selected = p);
    } else if (_selected != null) {
      final from = _selected!;
      final legal = Rules.legalMoves(st).any((m) => !m.isPlacement && m.from == from && m.to == p);
      if (legal) {
        ctl.move(from, p);
        setState(() => _selected = null);
      }
    }
  }

  int _targets(OnlineState s) {
    final g = s.game;
    final from = _selected;
    if (g == null || from == null || !s.myTurn) return 0;
    var mask = 0;
    for (final m in Rules.legalMoves(g.state)) {
      if (!m.isPlacement && m.from == from) mask |= bit(m.to);
    }
    return mask;
  }

  String _caption(OnlineState s, List<String> names) {
    final g = s.game!;
    final st = g.state;
    if (g.isOver) return 'Game over';
    final opp = s.opponent?.name ?? 'Your opponent';
    if (!s.myTurn) return 'Waiting for $opp...';
    if (g.pendingStep != null) return 'Machyas! Tap a glowing opponent token to eat it.';
    if (st.handOf(st.turn) > 0) {
      final two = st.placesLeft > 1 ? ' You place two tokens this turn.' : '';
      return 'Your turn: place a token on any point.$two';
    }
    return _selected == null ? 'Your turn: tap one of your tokens to move it.' : 'Tap a glowing point to slide there.';
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen<OnlineState>(onlineControllerProvider, _onState);
    final s = ref.watch(onlineControllerProvider);
    final ctl = ref.read(onlineControllerProvider.notifier);
    final g = s.game;
    final tk = context.tokens;
    final prefs = ref.watch(settingsProvider).motion;
    if (g == null) {
      // between rooms / waiting for the first state
      return Scaffold(
        body: AuroraBackground(
          prefs: prefs,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final names = _names(s);
    final mySeat = s.mySeat ?? 0;
    final oppSeat = 1 - mySeat;
    final st = g.state;
    final remaining = ctl.remainingMs();
    final total = g.clock?.totalMs ?? 120000;
    final activeSeat = g.clock?.seat ?? st.turn;

    PlayerCard card(int seat) => PlayerCard(
          seat: seat,
          name: seat == mySeat ? '${names[seat]} (you)' : names[seat],
          toPlace: st.handOf(seat),
          onBoard: popCount(st.maskOf(seat)),
          eaten: g.eaten.length > seat ? g.eaten[seat] : 0,
          active: st.turn == seat && !g.isOver,
        );

    final opponentAway = s.opponentReconnectDeadlineMs != null && !g.isOver;
    final away = opponentAway
        ? ((s.opponentReconnectDeadlineMs! - ctl.serverNow) / 1000).ceil().clamp(0, 999)
        : 0;

    return Scaffold(
      body: AuroraBackground(
        prefs: prefs,
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
                            SizedBox(
                              height: h * 0.14,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: math.min(MediaQuery.sizeOf(context).width, 640) - tk.space2 * 2,
                                  child: Row(
                                    children: [
                                      Expanded(child: card(oppSeat)),
                                      SizedBox(width: tk.space1),
                                      Opacity(
                                        opacity: g.isOver ? 0.5 : 1,
                                        child: TimerRing(
                                          progress: total == 0 ? 0 : remaining / total,
                                          secondsLeft: (remaining / 1000).ceil(),
                                          accent: activeSeat == mySeat ? tk.violet : tk.aqua,
                                        ),
                                      ),
                                      if (!ref.watch(hideEmotesProvider) && !g.isOver)
                                        Semantics(
                                          button: true,
                                          label: 'Emotes',
                                          child: InkResponse(
                                            onTap: () => showEmoteSheet(context),
                                            radius: 28,
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: Icon(Icons.emoji_emotions_outlined, color: tk.textMuted),
                                            ),
                                          ),
                                        ),
                                      Semantics(
                                        button: true,
                                        label: 'Leave game',
                                        child: InkResponse(
                                          onTap: widget.onLeave,
                                          radius: 28,
                                          child: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Icon(Icons.exit_to_app_rounded, color: tk.textMuted),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: h * 0.58,
                              child: Column(
                                children: [
                                  SizedBox(height: 34, child: Center(child: _Chip(state: s, game: g))),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, b) {
                                        final side = math.min(b.maxWidth, b.maxHeight - 8);
                                        return Center(
                                          child: SizedBox.square(
                                            dimension: side,
                                            child: GlassPanel(
                                              padding: const EdgeInsets.all(6),
                                              child: BoardView(
                                                game: st,
                                                selected: _selected,
                                                targets: _targets(s),
                                                captureMask: s.myTurn ? g.pendingTargets : 0,
                                                pending: g.pendingStep ?? s.optimistic,
                                                lastResult: s.lastResult,
                                                fxSerial: s.fxSerial,
                                                phutasLines: g.phutas?.lines ?? 0,
                                                phutasSerial: 0,
                                                prefs: prefs,
                                                onPointTap: (p) => _tap(p, s),
                                                onFxDone: (_) {},
                                                seatNames: names,
                                                semanticsLabel: 'Naw Tin board. ${_caption(s, names)}',
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
                                      child: Text(
                                        _caption(s, names),
                                        key: ValueKey(_caption(s, names)),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        style: tk.body(NawTinTokens.scaleXS, color: tk.textPrimary.withValues(alpha: 0.85)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: h * 0.28,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: math.min(MediaQuery.sizeOf(context).width, 640) - tk.space2 * 2,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      card(mySeat),
                                      SizedBox(height: tk.space2),
                                      ActionDock(
                                        phutasReady: _phutasReady(s),
                                        onPhutas: ctl.pressPhutas,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_bubble != null && emoteSpec(_bubble!.id) != null)
              Align(
                alignment: Alignment(0, _bubble!.seat == mySeat ? 0.62 : -0.66),
                child: EmoteBubble(spec: emoteSpec(_bubble!.id)!, fromYou: _bubble!.seat == mySeat),
              ),
            CallBannerOverlay(items: _banners, serial: _bannerSerial),
            // our own connection trouble, or the opponent's: the game is held, never forfeited
            if (!s.conn.isOnline || opponentAway)
              Positioned(
                left: tk.space2,
                right: tk.space2,
                top: MediaQuery.paddingOf(context).top + 4,
                child: _StatusBanner(
                  text: !s.conn.isOnline
                      ? 'Connection lost. Reconnecting... your game is waiting.'
                      : '${s.opponent?.name ?? 'Your opponent'} lost connection. Waiting ${away}s for them to come back.',
                ),
              ),
            if (g.isOver || s.room?.status == 'finished')
              _GameOverPanel(state: s, names: names, onLeave: widget.onLeave),
          ],
        ),
      ),
    );
  }

  /// PHUTAS is available when the server says the player has a line to warn about.
  bool _phutasReady(OnlineState s) {
    final p = s.game?.phutas;
    return !(s.game?.isOver ?? true) && s.conn.isOnline && p != null && p.seat == s.mySeat && p.lines != 0;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.state, required this.game});
  final OnlineState state;
  final GameView game;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final capture = game.pendingStep != null && state.myTurn;
    final label = game.isOver
        ? 'GAME OVER'
        : capture
            ? 'EAT A TOKEN'
            : (state.myTurn ? 'YOUR TURN' : 'THEIR TURN');
    final color = capture ? tk.danger : (state.myTurn ? tk.violet : tk.aqua);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tk.radiusL),
        color: color.withValues(alpha: 0.22),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: tk.heading(NawTinTokens.scaleXS).copyWith(letterSpacing: 1.6)),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tk.radiusM),
          color: tk.amber.withValues(alpha: 0.95),
        ),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tk.ink)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: tk.body(NawTinTokens.scaleXS, color: tk.ink))),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- game over

class _GameOverPanel extends ConsumerWidget {
  const _GameOverPanel({required this.state, required this.names, required this.onLeave});

  final OnlineState state;
  final List<String> names;
  final VoidCallback onLeave;

  String _reason(OnlineState s) {
    final g = s.game!;
    final winner = g.state.result?.winner;
    final loser = winner == null ? null : names[1 - winner];
    return switch (g.endReason) {
      EndReason.tokensReduced => 'Reduced to two tokens.',
      EndReason.noLegalMoves => 'No legal move left.',
      EndReason.repetition => 'The same position came up three times.',
      EndReason.disqualified => 'Out of time twice in a row.',
      EndReason.abandoned => '${loser ?? 'A player'} left and did not come back.',
      EndReason.forfeit => '${loser ?? 'A player'} left the game.',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final ctl = ref.read(onlineControllerProvider.notifier);
    final g = state.game!;
    final winner = g.state.result?.winner;
    final iWon = winner != null && winner == state.mySeat;
    final color = winner == null ? tk.gold : tk.seatColor(winner);
    final title = winner == null ? 'DRAW' : (iWon ? 'YOU WIN' : '${names[winner].toUpperCase()} WINS');
    final room = state.room;
    final opp = state.opponent;
    final offeredBy = room?.rematchOfferedBy;
    final iOffered = offeredBy != null && offeredBy == state.userId;
    final oppOffered = offeredBy != null && !iOffered;
    final canRematch = opp != null && opp.connected && state.conn.isOnline;

    final String rematchLabel;
    final VoidCallback? rematchTap;
    if (oppOffered) {
      rematchLabel = 'Accept rematch';
      rematchTap = canRematch ? ctl.acceptRematch : null;
    } else if (iOffered) {
      rematchLabel = 'Waiting for ${opp?.name ?? 'them'}...';
      rematchTap = null;
    } else {
      rematchLabel = canRematch ? 'Rematch' : 'Your friend has left';
      rematchTap = canRematch ? ctl.offerRematch : null;
    }

    int stat(List<int> v, int seat) => v.length > seat ? v[seat] : 0;

    Widget row(String label, List<int> v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text('${stat(v, 0)}', style: tk.digits(NawTinTokens.scaleM, color: tk.coral)),
              Expanded(child: Text(label, textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleXS))),
              Text('${stat(v, 1)}', style: tk.digits(NawTinTokens.scaleM, color: tk.aqua)),
            ],
          ),
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        Center(
          child: Padding(
            padding: EdgeInsets.all(tk.space3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: GlassPanel(
                  glow: color,
                  padding: EdgeInsets.all(tk.space3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: GlowText(
                            title,
                            style: tk.display(NawTinTokens.scaleL + 6),
                            colors: [tk.goldGlow, color],
                            glow: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_reason(state), textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleS)),
                      SizedBox(height: tk.space2),
                      Row(
                        children: [
                          Expanded(child: Text(names[0], style: tk.body(NawTinTokens.scaleXS, color: tk.coral))),
                          Text(names[1], style: tk.body(NawTinTokens.scaleXS, color: tk.aqua)),
                        ],
                      ),
                      row('Tokens eaten', g.eaten),
                      row('Lines formed', g.lines),
                      row('Begi / Treghi', g.swings),
                      SizedBox(height: tk.space3),
                      NawButton(label: rematchLabel, icon: Icons.replay_rounded, onPressed: rematchTap),
                      SizedBox(height: tk.space1),
                      if (opp != null)
                        TextButton.icon(
                          key: const ValueKey('report-button'),
                          onPressed: state.reported
                              ? null
                              : () async {
                                  final reason = await showReportSheet(context, opp.name);
                                  if (reason == null || !context.mounted) return;
                                  if (ctl.report(reason)) {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(const SnackBar(content: Text('Thanks, your report was sent.')));
                                  }
                                },
                          icon: Icon(state.reported ? Icons.check_rounded : Icons.flag_outlined, size: 18),
                          label: Text(state.reported ? 'Reported' : 'Report ${opp.name}'),
                        ),
                      NawButton(
                        label: 'Home',
                        style: NawButtonStyle.secondary,
                        onPressed: () {
                          ctl.leaveRoom();
                          Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/home');
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
