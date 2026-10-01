import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/naw_button.dart';
import '../online_controller.dart';
import '../online_state.dart';
import '../widgets/online_widgets.dart';

/// "Join with a code": six boxes, a paste shortcut when the clipboard holds a
/// code (the share message puts it there for the friend), and plain-language
/// errors. It closes itself once the server has put us in the room.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  late final TextEditingController _code = TextEditingController(text: _clean(widget.initialCode ?? ''));
  final FocusNode _focus = FocusNode();
  String? _clipboardCode;
  bool _joining = false;
  late final OnlineGameController _ctl = ref.read(onlineControllerProvider.notifier);

  static String _clean(String raw) {
    final t = normalizeRoomCode(raw);
    return t.length > roomCodeLength ? t.substring(0, roomCodeLength) : t;
  }

  @override
  void initState() {
    super.initState();
    // not during the first build: providers may not change while the tree builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctl.clearRoomEnd();
    });
    _readClipboard();
  }

  /// A code someone texted you: copy it, open Join, tap the chip.
  Future<void> _readClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      // the code can sit inside a longer message: take the first 6-symbol word
      for (final m in RegExp(r'[A-Za-z0-9]{6}').allMatches(text)) {
        final c = normalizeRoomCode(m.group(0)!);
        if (isValidRoomCode(c)) {
          if (mounted && c != _code.text) setState(() => _clipboardCode = c);
          return;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    // leave no stale "not found" behind for the menu
    Future.microtask(_ctl.clearRoomEnd);
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.length == roomCodeLength;

  void _submit() {
    if (!_complete || _joining) return;
    setState(() => _joining = true);
    _ctl.clearRoomEnd();
    _ctl.joinRoom(_code.text);
  }

  String? _problem(OnlineState s) {
    final e = s.roomEnd;
    if (e != null) {
      return switch (e) {
        RoomEnd.notFound => "We couldn't find a game with that code. Check it and try again.",
        RoomEnd.full => 'That game already has two players.',
        RoomEnd.expired => 'That room has expired. Ask your friend for a new code.',
        RoomEnd.closed => 'That room is closed. Ask your friend for a new code.',
      };
    }
    final err = s.error;
    if (err != null) {
      return switch (err.code) {
        ErrorCodes.rateLimited => 'Too many tries. Wait a moment, then try again.',
        ErrorCodes.alreadyInRoom => 'You are already in a game. Go back to rejoin it.',
        'not_connected' => "You're not connected to the server yet.",
        _ => err.message,
      };
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final s = ref.watch(onlineControllerProvider);
    ref.listen<OnlineState>(onlineControllerProvider, (prev, next) {
      if (next.room != null && mounted) {
        Navigator.of(context).maybePop(); // the lobby takes over
        return;
      }
      if (_joining && (next.roomEnd != null || next.error != null)) {
        setState(() => _joining = false);
      }
    });
    final problem = _problem(s);

    return OnlineFrame(
      title: 'Join a game',
      onBack: () => Navigator.of(context).maybePop(),
      trailing: ConnectionDot(state: s.conn, showLabel: true),
      child: ListView(
        padding: EdgeInsets.only(top: tk.space3),
        children: [
          Text(
            'Enter the 6-character code your friend sent you.',
            textAlign: TextAlign.center,
            style: tk.body(NawTinTokens.scaleS, color: tk.textMuted),
          ),
          SizedBox(height: tk.space3),
          CodeBoxes(
            controller: _code,
            focusNode: _focus,
            error: problem != null,
            onChanged: (_) {
              if (s.roomEnd != null || s.error != null) _ctl.clearRoomEnd();
              setState(() {});
            },
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: tk.space2),
          SizedBox(
            height: 48,
            child: Center(
              child: problem != null
                  ? Semantics(
                      liveRegion: true,
                      child: Text(problem, textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleXS, color: tk.danger)),
                    )
                  : (_clipboardCode != null && _code.text.isEmpty)
                      ? ActionChip(
                          avatar: const Icon(Icons.content_paste_rounded, size: 18),
                          label: Text('Paste $_clipboardCode'),
                          onPressed: () {
                            _code.text = _clipboardCode!;
                            setState(() => _clipboardCode = null);
                          },
                        )
                      : null,
            ),
          ),
          SizedBox(height: tk.space2),
          NawButton(
            label: _joining ? 'Joining...' : 'Join',
            icon: Icons.login_rounded,
            onPressed: _complete && !_joining && s.conn.isOnline ? _submit : null,
          ),
          if (!s.conn.isOnline)
            Padding(
              padding: EdgeInsets.only(top: tk.space1),
              child: Text('Connecting to the server...', textAlign: TextAlign.center, style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted)),
            ),
        ],
      ),
    );
  }
}
