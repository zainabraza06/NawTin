import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_router.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/naw_button.dart';
import '../online_controller.dart';
import '../../../services/online/online_service.dart';
import 'online_widgets.dart';

/// Home screen's "Play Online" button, with the connection dot once online play
/// has been opened. The online layer is only created when this is built, and it
/// never connects by itself.
class PlayOnlineButton extends ConsumerWidget {
  const PlayOnlineButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(onlineControllerProvider.select((s) => s.conn));
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        NawButton(
          label: 'Play Online',
          caption: 'Private room with a friend',
          icon: Icons.public_rounded,
          onPressed: () => Navigator.of(context).pushNamed(Routes.online),
        ),
        if (conn.phase != ConnPhase.idle)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: ConnectionDot(state: conn),
          ),
      ],
    );
  }
}

/// "Game in progress" card: shown when a room is saved on this device (the app
/// was closed or the connection dropped mid-game). One tap rejoins; the X
/// removes it, after asking, because a game that is still running is forfeited.
class RejoinCard extends ConsumerWidget {
  const RejoinCard({super.key});

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this game?'),
        content: const Text('If the game is still going you will forfeit it, and your friend wins.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(onlineControllerProvider.notifier).abandonSaved();
      // not connected: forget it locally; the room closes by itself
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final code = ref.watch(onlineControllerProvider.select((s) => s.rejoinCode));
    if (code == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: tk.space2),
      child: Semantics(
        container: true,
        label: 'Game in progress, room $code',
        child: GlassPanel(
          glow: tk.lime,
          padding: EdgeInsets.fromLTRB(tk.space2, tk.space1, 4, tk.space1),
          child: Row(
            children: [
              Icon(Icons.sports_esports_rounded, color: tk.lime),
              SizedBox(width: tk.space1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Game in progress', style: tk.heading(NawTinTokens.scaleS)),
                    Text('Room $code', style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted)),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.online, arguments: true),
                child: const Text('Rejoin'),
              ),
              IconButton(
                tooltip: 'Remove this game',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => _remove(context, ref),
                icon: Icon(Icons.close_rounded, color: tk.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
