// ignore_for_file: avoid_print
// Replays a Naw Tin game record and finds where the AI went wrong.
//
//   dart run tool/analyze_game.dart record.txt [--ai 1] [--depth 10] [--loss 60]
//
// In the app: after a game against the AI tap "Copy game record", paste the text
// into a file (or send it to the developer). For every AI move this searches the
// position deeply, compares the move that was played with the best one, and
// prints the moves that lose more than --loss points (100 = one token). It also
// prints the evaluation after every move (from the AI's point of view), so you
// can see where the human took over.
import 'dart:io';

import 'package:naw_tin_core/naw_tin_core.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/analyze_game.dart <record.txt> [--ai SEAT] [--depth N] [--loss POINTS]');
    exit(64);
  }
  String opt(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final rec = GameTranscript.parse(File(args.first).readAsStringSync());
  if (rec == null) {
    stderr.writeln('That file is not a Naw Tin game record (it should start with NAWTIN1).');
    exit(65);
  }
  Rules.placementRule = rec.meta['rule'] == 'openingAndClosingDouble'
      ? PlacementRule.openingAndClosingDouble
      : PlacementRule.symmetricOpening;
  final depth = int.parse(opt('--depth', '10'));
  final threshold = int.parse(opt('--loss', '60'));
  final aiSeat = int.tryParse(opt('--ai', rec.meta['ai'] ?? ''));
  // a reference that is stronger than the shipped levels
  final cfg = AiConfig.hard.withDepth(depth).withTime(600000).strictTime().withVariety(0);

  final positions = rec.positions();
  print('game: ${rec.meta}');
  print('${rec.moves.length} plies, AI seat: ${aiSeat ?? 'unknown (all moves analysed)'}, reference depth $depth\n');
  print('ply  seat  move          eval(AI view)  note');

  int value(GameState s, int d) => Searcher(cfg).valueOf(s, d);
  var flagged = 0;
  for (var i = 0; i < rec.moves.length; i++) {
    final pos = positions[i], after = positions[i + 1], m = rec.moves[i];
    final mover = pos.turn;
    final povSeat = aiSeat ?? mover; // evaluation from the AI's side (or the mover's)
    int povValue(GameState s) {
      if (s.isOver) {
        final r = s.result!;
        return r.isDraw ? 0 : (r.winner == povSeat ? Evaluator.win : -Evaluator.win);
      }
      final v = value(s, depth);
      return s.turn == povSeat ? v : -v;
    }

    // value of the played move vs. the best available, both for the mover
    int moverValue(GameState s) {
      final v = povValue(s);
      return povSeat == mover ? v : -v;
    }

    final played = moverValue(after);
    var best = played;
    Move? bestMove;
    if (aiSeat == null || mover == aiSeat) {
      for (final alt in Rules.legalMoves(pos)) {
        if (alt == m) continue;
        final v = moverValue(Rules.apply(pos, alt));
        if (v > best) {
          best = v;
          bestMove = alt;
        }
      }
    }
    final loss = best - played;
    final note = StringBuffer();
    if (aiSeat != null && mover != aiSeat) note.write('human');
    if ((aiSeat == null || mover == aiSeat) && loss >= threshold && bestMove != null) {
      note.write('MISTAKE: lost $loss, better was ${GameTranscript.encodeMove(bestMove)}');
      flagged++;
    }
    final eval = povValue(after);
    print('${(i + 1).toString().padLeft(3)}  ${mover.toString().padLeft(4)}  '
        '${GameTranscript.encodeMove(m).padRight(12)}  ${eval.abs() >= Evaluator.win - 200 ? (eval > 0 ? 'WIN ' : 'LOSS') : eval.toString().padLeft(5)}          $note');
  }
  print('\n$flagged AI move(s) lost at least $threshold points against the reference.');
}
