import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/board_view.dart';
import '../online_controller.dart';
import '../online_state.dart';

/// DEBUG BUILDS ONLY (the route is compiled out of release builds).
///
/// A bare-bones console for the online layer: connect, create / join a room,
/// play with the real board, watch events and the clock. The polished online
/// screens come in the next stage.
class OnlineDebugScreen extends ConsumerStatefulWidget {
  const OnlineDebugScreen({super.key});

  @override
  ConsumerState<OnlineDebugScreen> createState() => _OnlineDebugScreenState();
}

class _OnlineDebugScreenState extends ConsumerState<OnlineDebugScreen> with WidgetsBindingObserver {
  final _code = TextEditingController();
  late final TextEditingController _server =
      TextEditingController(text: ref.read(debugServerProvider) ?? '');
  Timer? _tick;
  int? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // repaint the countdown a few times a second
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  /// Backgrounding / closing the app must NEVER leave the room: the lifecycle
  /// only reaches the connection layer, which treats it as a drop.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      ref.read(onlineControllerProvider.notifier).onLifecycle(state);

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the game?'),
        content: const Text("You'll forfeit."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) ref.read(onlineControllerProvider.notifier).leaveGame();
  }

  void _tap(int p, OnlineState s) {
    final ctl = ref.read(onlineControllerProvider.notifier);
    final g = s.game;
    if (g == null || !s.myTurn) return;
    if (g.pendingStep != null) {
      if (g.pendingTargets & bit(p) != 0) ctl.capture(p);
      return;
    }
    final st = g.state;
    if (st.handOf(st.turn) > 0) {
      ctl.place(p);
      return;
    }
    final mine = st.maskOf(st.turn);
    if (mine & bit(p) != 0) {
      setState(() => _selected = p);
    } else if (_selected != null) {
      ctl.move(_selected!, p);
      setState(() => _selected = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final s = ref.watch(onlineControllerProvider);
    final ctl = ref.read(onlineControllerProvider.notifier);
    final cfg = ref.watch(onlineConfigProvider);
    final profile = ref.watch(onlineProfileProvider);
    final remaining = ctl.remainingMs();
    final style = tk.body(13, color: tk.textPrimary);

    Widget row(List<Widget> children) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 6, children: children),
        );

    return Scaffold(
      backgroundColor: tk.bgTop,
      appBar: AppBar(title: const Text('Online (debug)'), backgroundColor: tk.bgMid),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text('server: $cfg', style: style),
            row([
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _server,
                  decoration: const InputDecoration(labelText: 'server address (ws://PC-IP:8080/ws)', isDense: true),
                  keyboardType: TextInputType.url,
                ),
              ),
              FilledButton(
                onPressed: () => ref.read(debugServerProvider.notifier).set(_server.text),
                child: const Text('Use'),
              ),
            ]),
            Text('user: ${s.userId ?? '-'}   name: ${profile.name}', style: style),
            Text(
              'connection: ${s.conn.phase.name}'
              '${s.conn.problem != null ? ' (${s.conn.problem!.name}, try ${s.conn.attempt})' : ''}'
              '${s.conn.stopReason != null ? ' STOPPED: ${s.conn.stopReason!.name}' : ''}'
              '   ping ${s.pingMs} ms   clock offset ${s.offsetMs} ms',
              style: style,
            ),
            if (s.outdated)
              Text('Please update the app to play online.', style: style.copyWith(color: tk.amber)),
            if (s.error != null)
              Text('error: ${s.error!.code} - ${s.error!.message}', style: style.copyWith(color: tk.danger)),
            if (s.roomEnd != null) Text('room: ${s.roomEnd!.name}', style: style.copyWith(color: tk.amber)),
            const Divider(),
            row([
              FilledButton(onPressed: ctl.connect, child: const Text('Connect')),
              OutlinedButton(onPressed: ctl.disconnect, child: const Text('Disconnect')),
              FilledButton(onPressed: s.conn.isOnline ? ctl.createRoom : null, child: const Text('Create room')),
              if (s.rejoinCode != null)
                FilledButton(onPressed: ctl.rejoin, child: Text('Rejoin ${s.rejoinCode}')),
            ]),
            row([
              SizedBox(
                width: 140,
                child: TextField(controller: _code, decoration: const InputDecoration(labelText: 'code'), textCapitalization: TextCapitalization.characters),
              ),
              FilledButton(onPressed: () => ctl.joinRoom(_code.text), child: const Text('Join')),
            ]),
            if (s.room != null) ...[
              const Divider(),
              Text('ROOM ${s.room!.code}  status ${s.room!.status}  you are ${s.isHost ? 'host' : 'guest'}  seat ${s.mySeat ?? '-'}', style: style),
              for (final p in s.room!.players)
                Text(
                  '  ${p.name} seat ${p.seat ?? '-'}  ${p.connected ? 'online' : 'AWAY'}  ready ${p.ready}  ${p.pingMs}ms',
                  style: style,
                ),
              if (s.opponentReconnectDeadlineMs != null)
                Text(
                  'Opponent disconnected, reconnecting... '
                  '${((s.opponentReconnectDeadlineMs! - ctl.serverNow) / 1000).ceil().clamp(0, 99)}s',
                  style: style.copyWith(color: tk.amber),
                ),
              row([
                OutlinedButton(onPressed: () => ctl.setReady(true), child: const Text('Ready')),
                FilledButton(onPressed: ctl.start, child: const Text('Start (host)')),
                OutlinedButton(onPressed: ctl.offerRematch, child: const Text('Offer rematch')),
                OutlinedButton(onPressed: ctl.acceptRematch, child: const Text('Accept rematch')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: tk.danger),
                  onPressed: _confirmLeave,
                  child: const Text('Leave game...'),
                ),
              ]),
            ],
            if (s.game != null) ...[
              const Divider(),
              Text(
                'turn: seat ${s.game!.state.turn}${s.myTurn ? ' (YOU)' : ''}   '
                'clock: ${(remaining / 1000).toStringAsFixed(1)} s   '
                'timeouts ${s.game!.timeouts}   rev ${s.game!.rev}'
                '${s.game!.isOver ? '   GAME OVER: winner ${s.game!.state.result?.winner} (${s.game!.endReason})' : ''}',
                style: style,
              ),
              if (s.game!.pendingStep != null)
                Text('Machyas! tap a glowing token to eat', style: style.copyWith(color: tk.lime)),
              const SizedBox(height: 8),
              Center(
                child: SizedBox(
                  width: 340,
                  child: BoardView(
                    game: s.game!.state,
                    selected: _selected,
                    targets: 0,
                    captureMask: s.myTurn ? s.game!.pendingTargets : 0,
                    pending: s.game!.pendingStep ?? s.optimistic,
                    lastResult: s.lastResult,
                    fxSerial: s.fxSerial,
                    phutasLines: s.game!.phutas?.lines ?? 0,
                    phutasSerial: 0,
                    onPointTap: (p) => _tap(p, s),
                    onFxDone: (_) {},
                  ),
                ),
              ),
              row([
                OutlinedButton(onPressed: ctl.pressPhutas, child: const Text('Phutas')),
                OutlinedButton(onPressed: () => ctl.emote('nice_one'), child: const Text('Nice one')),
                OutlinedButton(onPressed: () => ctl.emote('good_game'), child: const Text('Good game')),
              ]),
            ],
            const Divider(),
            Text('events', style: style.copyWith(fontWeight: FontWeight.bold)),
            for (final e in s.events.reversed.take(14))
              Text('#${e.rev} ${e.kind} seat ${e.seat} ${e.data}', style: style.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
