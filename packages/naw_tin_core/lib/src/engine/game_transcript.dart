import 'game_state.dart';
import 'move.dart';
import 'rules.dart';

/// A finished (or running) game as plain text: a header line and the moves.
///
/// ```
/// NAWTIN1 mode=vsAi level=hard ai=1 rule=symmetricOpening
/// p9 p12 p4 s3-2x20 s12-13 ...
/// ```
///
/// `p9` places on point 9, `s3-2` slides 3 to 2, and a trailing `x20` is the
/// token eaten by that move. The text is easy to copy out of the app and paste
/// into tools/analyze_game.dart, which replays it and flags where the AI went
/// wrong.
final class GameTranscript {
  const GameTranscript(this.meta, this.moves);

  /// Header fields such as `mode`, `level`, `ai` (the AI's seat), `rule`.
  final Map<String, String> meta;
  final List<Move> moves;

  static const String tag = 'NAWTIN1';

  static String encodeMove(Move m) {
    final base = m.isPlacement ? 'p${m.to}' : 's${m.from}-${m.to}';
    return m.hasCapture ? '${base}x${m.capture}' : base;
  }

  static final RegExp _token = RegExp(r'^(?:p(\d{1,2})|s(\d{1,2})-(\d{1,2}))(?:x(\d{1,2}))?$');

  /// Null when [t] is not a well-formed move token.
  static Move? decodeMove(String t) {
    final m = _token.firstMatch(t);
    if (m == null) return null;
    final cap = m.group(4) == null ? -1 : int.parse(m.group(4)!);
    if (m.group(1) != null) return Move.place(int.parse(m.group(1)!), capture: cap);
    return Move.slide(int.parse(m.group(2)!), int.parse(m.group(3)!), capture: cap);
  }

  String encode() {
    final head = StringBuffer(tag);
    for (final e in meta.entries) {
      head.write(' ${e.key}=${e.value}');
    }
    return '$head\n${moves.map(encodeMove).join(' ')}';
  }

  /// Parses [text]; null if it is not a record.
  static GameTranscript? parse(String text) {
    final lines = text.trim().split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return null;
    final head = lines.first.trim().split(RegExp(r'\s+'));
    if (head.isEmpty || head.first != tag) return null;
    final meta = <String, String>{};
    for (final part in head.skip(1)) {
      final i = part.indexOf('=');
      if (i > 0) meta[part.substring(0, i)] = part.substring(i + 1);
    }
    final moves = <Move>[];
    final body = lines.skip(1).join(' ').trim();
    if (body.isNotEmpty) {
      for (final tok in body.split(RegExp(r'\s+'))) {
        final m = decodeMove(tok);
        if (m == null) return null;
        moves.add(m);
      }
    }
    return GameTranscript(meta, moves);
  }

  /// The position before each move, then the final one (length = moves + 1).
  /// Throws if a move is not legal from its position.
  List<GameState> positions() {
    final out = <GameState>[GameState.initial()];
    for (final m in moves) {
      final s = out.last;
      if (!Rules.legalMoves(s).contains(m)) {
        throw StateError('move ${encodeMove(m)} is not legal at ply ${out.length}');
      }
      out.add(Rules.apply(s, m));
    }
    return out;
  }
}
