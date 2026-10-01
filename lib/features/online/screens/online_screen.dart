import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_router.dart';
import '../../../services/connectivity.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/naw_button.dart';
import '../online_controller.dart';
import '../online_issue.dart';
import '../online_messages.dart';
import '../online_state.dart';
import '../widgets/online_widgets.dart';
import 'lobby_view.dart';
import 'online_game_view.dart';

/// Where the app lives in the store (the "Please update" action opens it).
const _storeUrl = 'market://details?id=com.zainab.nawtin';
const _storeWebUrl = 'https://play.google.com/store/apps/details?id=com.zainab.nawtin';

/// The one online route. It shows whichever page the current state calls for:
/// a designed problem screen, the menu, the lobby or the game.
class OnlineScreen extends ConsumerStatefulWidget {
  const OnlineScreen({super.key, this.rejoin = false});

  /// Opened from the "Rejoin game" card: rejoin as soon as we are connected.
  final bool rejoin;

  @override
  ConsumerState<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends ConsumerState<OnlineScreen> {
  late bool _pendingRejoin = widget.rejoin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctl = ref.read(onlineControllerProvider.notifier);
      ctl.connect();
      _maybeRejoin(ref.read(onlineControllerProvider));
    });
  }

  void _maybeRejoin(OnlineState s) {
    if (_pendingRejoin && s.conn.isOnline) {
      _pendingRejoin = false;
      ref.read(onlineControllerProvider.notifier).rejoin();
    }
  }

  Future<void> _onIssueAction(IssueAction a) async {
    final ctl = ref.read(onlineControllerProvider.notifier);
    switch (a) {
      case IssueAction.back:
        if (mounted) Navigator.of(context).maybePop();
      case IssueAction.update:
        try {
          if (!await launchUrl(Uri.parse(_storeUrl))) {
            await launchUrl(Uri.parse(_storeWebUrl), mode: LaunchMode.externalApplication);
          }
        } catch (_) {
          await launchUrl(Uri.parse(_storeWebUrl), mode: LaunchMode.externalApplication);
        }
      case IssueAction.useHere:
      case IssueAction.retry:
        ctl.connect();
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    );
    return ok == true;
  }

  /// Back button / swipe. A live game is only left through the confirmed
  /// forfeit; a lobby or finished game is left immediately.
  Future<void> _onBack(OnlineState s) async {
    final ctl = ref.read(onlineControllerProvider.notifier);
    final room = s.room;
    if (room == null) {
      Navigator.of(context).pop();
      return;
    }
    if (room.status == 'playing' && !(s.game?.isOver ?? false)) {
      if (await _confirm('Leave the game?', 'You will forfeit and your opponent wins.', 'Leave')) {
        ctl.leaveRoom();
      }
      return;
    }
    if (room.status == 'lobby' || room.status == 'waiting') {
      if (await _confirm('Leave this room?', 'Your friend will not be able to join with this code any more.', 'Leave')) {
        ctl.leaveRoom();
      }
      return;
    }
    ctl.leaveRoom();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OnlineState>(onlineControllerProvider, (_, next) => _maybeRejoin(next));
    final s = ref.watch(onlineControllerProvider);
    final hasNetwork = ref.watch(networkProvider).value ?? true;
    final issue = issueFor(s.conn, hasNetwork: hasNetwork);
    final room = s.room;
    // mid-game hiccups keep the board and show a banner; only a hard stop
    // (outdated, replaced, sign-in) replaces it
    final blocking = issue != null && (room == null || s.conn.isStopped);

    final Widget page;
    String? title;
    if (blocking) {
      title = 'Play Online';
      page = IssueView(issue: issue, onAction: _onIssueAction);
    } else if (room == null && s.roomEnd != null) {
      title = 'Play Online';
      page = _RoomEndView(end: s.roomEnd!, onDone: ref.read(onlineControllerProvider.notifier).clearRoomEnd);
    } else if (room == null || room.status == 'closed') {
      title = 'Play Online';
      page = const _MenuView();
    } else if (room.status == 'playing' || room.status == 'finished') {
      page = OnlineGameView(onLeave: () => _onBack(s));
    } else {
      title = 'Your room';
      page = LobbyView(onLeave: () => _onBack(s));
    }

    final inGame = room != null && (room.status == 'playing' || room.status == 'finished') && !blocking;
    return PopScope(
      canPop: room == null || blocking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack(s);
      },
      child: inGame
          ? page // the game screen draws its own frame
          : OnlineFrame(
              title: title,
              onBack: () => _onBack(s),
              trailing: ConnectionDot(state: s.conn, showLabel: true),
              child: page,
            ),
    );
  }
}

// ---------------------------------------------------------------- menu

class _MenuView extends ConsumerWidget {
  const _MenuView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final s = ref.watch(onlineControllerProvider);
    final ctl = ref.read(onlineControllerProvider.notifier);
    final profile = ref.watch(onlineProfileProvider);
    final online = s.conn.isOnline;

    return ListView(
      padding: EdgeInsets.only(top: tk.space2, bottom: tk.space3),
      children: [
        GlassPanel(
          padding: EdgeInsets.symmetric(horizontal: tk.space2, vertical: tk.space2),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: tk.violet.withValues(alpha: 0.25),
                child: Text(
                  profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                  style: tk.heading(NawTinTokens.scaleM),
                ),
              ),
              SizedBox(width: tk.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Playing as', style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted)),
                    Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.heading(NawTinTokens.scaleS)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _editName(context, ref),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
        SizedBox(height: tk.space3),
        NawButton(
          label: 'Create a room',
          caption: online ? 'Get a code to share with a friend' : 'Connecting...',
          icon: Icons.add_circle_outline_rounded,
          onPressed: online ? ctl.createRoom : null,
        ),
        SizedBox(height: tk.space2),
        NawButton(
          label: 'Join with a code',
          caption: online ? 'Enter the 6-character code' : 'Connecting...',
          icon: Icons.keyboard_rounded,
          style: NawButtonStyle.secondary,
          onPressed: online ? () => Navigator.of(context).pushNamed(Routes.onlineJoin) : null,
        ),
        if (s.error != null) ...[
          SizedBox(height: tk.space2),
          Semantics(
            liveRegion: true,
            child: Text(errorText(s.error!), textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleXS, color: tk.danger)),
          ),
        ],
        SizedBox(height: tk.space3),
        Text(
          'Private rooms: you and a friend, each on your own phone. No account needed.',
          textAlign: TextAlign.center,
          style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted),
        ),
      ],
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: ref.read(onlineProfileProvider).name);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Your name'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 16,
            decoration: InputDecoration(helperText: '2 to 16 characters', errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (ref.read(onlineProfileProvider.notifier).setName(c.text)) {
                  Navigator.pop(ctx);
                } else {
                  setState(() => error = 'Please pick another name.');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
  }
}

// ------------------------------------------------------------ room ended

class _RoomEndView extends StatelessWidget {
  const _RoomEndView({required this.end, required this.onDone});
  final RoomEnd end;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final (title, body) = switch (end) {
      RoomEnd.expired => ('This room has expired', 'Rooms close after 10 minutes of waiting. Ask your friend for a new code, or make one yourself.'),
      RoomEnd.notFound => ('No game with that code', 'It may have ended, or the code was typed wrongly.'),
      RoomEnd.full => ('That game is full', 'It already has two players.'),
      RoomEnd.closed => ('The room was closed', 'The game is no longer available.'),
    };
    return Center(
      child: GlassPanel(
        padding: EdgeInsets.all(tk.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.meeting_room_outlined, size: 56, color: tk.amber),
            SizedBox(height: tk.space2),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(title, textAlign: TextAlign.center, style: tk.heading(NawTinTokens.scaleM)),
            ),
            SizedBox(height: tk.space1),
            Text(body, textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleS, color: tk.textMuted)),
            SizedBox(height: tk.space3),
            NawButton(label: 'OK', onPressed: onDone),
          ],
        ),
      ),
    );
  }
}
