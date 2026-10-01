import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/naw_button.dart';
import '../online_controller.dart';
import '../online_state.dart';

/// The text a share sends. The code is in the message, so it works from any
/// messaging app with no link or domain.
String shareMessage(String code) =>
    'Play Naw Tin with me! Open the app, tap Play Online, then Join with a code and enter: $code';

/// Waiting room: the code (tap to copy), a share button, who is here, ready /
/// start, and the 10-minute expiry.
class LobbyView extends ConsumerStatefulWidget {
  const LobbyView({super.key, required this.onLeave});

  final VoidCallback onLeave;

  @override
  ConsumerState<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends ConsumerState<LobbyView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 2)));
  }

  Future<void> _share(String code) async {
    try {
      await SharePlus.instance.share(ShareParams(text: shareMessage(code), subject: 'Naw Tin'));
    } catch (_) {
      // no share sheet available: fall back to copying the message
      await Clipboard.setData(ClipboardData(text: shareMessage(code)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied')));
    }
  }

  String _expiry(OnlineState s) {
    final at = s.room?.expiresAtMs;
    if (at == null) return '';
    final left = ((at - ref.read(onlineControllerProvider.notifier).serverNow) / 1000).ceil();
    if (left <= 0) return 'Closing...';
    return 'Room closes in ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final s = ref.watch(onlineControllerProvider);
    final ctl = ref.read(onlineControllerProvider.notifier);
    final room = s.room!;
    final me = s.me;
    final other = s.opponent;
    final bothHere = other != null;
    final otherReady = other?.ready ?? false;

    return ListView(
      padding: EdgeInsets.only(top: tk.space2, bottom: tk.space3),
      children: [
        GlassPanel(
          glow: tk.violet,
          padding: EdgeInsets.all(tk.space3),
          child: Column(
            children: [
              Text('ROOM CODE', style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted).copyWith(letterSpacing: 2)),
              SizedBox(height: tk.space1),
              Semantics(
                label: 'Room code ${room.code.split('').join(' ')}. Tap to copy.',
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(tk.radiusM),
                  onTap: () => _copy(room.code),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      room.code,
                      style: tk.digits(NawTinTokens.scaleXL).copyWith(letterSpacing: 6),
                    ),
                  ),
                ),
              ),
              SizedBox(height: tk.space1),
              Text(_expiry(s), style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted)),
              SizedBox(height: tk.space2),
              Row(
                children: [
                  Expanded(
                    child: NawButton(
                      label: 'Share',
                      icon: Icons.ios_share_rounded,
                      onPressed: () => _share(room.code),
                    ),
                  ),
                  SizedBox(width: tk.space1),
                  Expanded(
                    child: NawButton(
                      label: 'Copy',
                      icon: Icons.copy_rounded,
                      style: NawButtonStyle.secondary,
                      onPressed: () => _copy(room.code),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: tk.space3),
        _PlayerRow(name: me?.name ?? 'You', status: s.isHost ? 'Host' : (me?.ready == true ? 'Ready' : 'Not ready'), ready: s.isHost || me?.ready == true, connected: true, you: true),
        SizedBox(height: tk.space1),
        if (other == null)
          _WaitingRow()
        else
          _PlayerRow(
            name: other.name,
            status: !other.connected ? 'Disconnected' : (s.isHost ? (other.ready ? 'Ready' : 'Not ready yet') : 'Host'),
            ready: s.isHost ? other.ready : true,
            connected: other.connected,
          ),
        SizedBox(height: tk.space3),
        if (s.isHost)
          NawButton(
            label: 'Start game',
            icon: Icons.play_arrow_rounded,
            caption: !bothHere
                ? 'Waiting for your friend to join'
                : (!otherReady ? 'Waiting for your friend to get ready' : 'The coin flip decides who moves first'),
            onPressed: bothHere && otherReady && other.connected ? ctl.start : null,
          )
        else
          NawButton(
            label: me?.ready == true ? 'Not ready' : "I'm ready",
            icon: me?.ready == true ? Icons.close_rounded : Icons.check_rounded,
            caption: me?.ready == true ? 'Waiting for the host to start' : 'Tell the host you can play',
            style: me?.ready == true ? NawButtonStyle.secondary : NawButtonStyle.primary,
            onPressed: () => ctl.setReady(!(me?.ready ?? false)),
          ),
        if (s.error != null) ...[
          SizedBox(height: tk.space2),
          Semantics(
            liveRegion: true,
            child: Text(s.error!.message, textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleXS, color: tk.danger)),
          ),
        ],
        SizedBox(height: tk.space2),
        NawButton(label: 'Leave room', style: NawButtonStyle.ghost, onPressed: widget.onLeave),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.name, required this.status, required this.ready, required this.connected, this.you = false});

  final String name;
  final String status;
  final bool ready;
  final bool connected;
  final bool you;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = !connected ? tk.danger : (ready ? tk.lime : tk.amber);
    return Semantics(
      label: '${you ? 'You, ' : ''}$name, $status',
      excludeSemantics: true,
      child: GlassPanel(
        padding: EdgeInsets.symmetric(horizontal: tk.space2, vertical: tk.space2 - 4),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            SizedBox(width: tk.space2),
            Expanded(
              child: Text(you ? '$name (you)' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.heading(NawTinTokens.scaleS)),
            ),
            Text(status, style: tk.body(NawTinTokens.scaleXS, color: color)),
          ],
        ),
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return GlassPanel(
      padding: EdgeInsets.symmetric(horizontal: tk.space2, vertical: tk.space2),
      child: Row(
        children: [
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: tk.space2),
          Expanded(
            child: Text('Waiting for your friend...', style: tk.body(NawTinTokens.scaleS, color: tk.textMuted)),
          ),
        ],
      ),
    );
  }
}
