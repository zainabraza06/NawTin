// Self-play harness. Run from the project root:
//   dart run tool/self_play.dart [games] [hardMs] [easyMs]
//   e.g. dart run tool/self_play.dart 10 400 100
// ignore_for_file: avoid_print
// Prints Hard-vs-Easy, Hard-vs-Hard (seat fairness) and Medium-vs-Easy.
import 'package:nawtin/core/ai/ai.dart';
import 'package:nawtin/core/ai/self_play.dart';

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 10;
  final hardMs = args.length > 1 ? int.parse(args[1]) : 400;
  final easyMs = args.length > 2 ? int.parse(args[2]) : 100;

  void run(String title, AiConfig a, AiConfig b, {int n = 0, bool mirror = true}) {
    final sw = Stopwatch()..start();
    final stats = playMatch(
      a,
      b,
      games: n == 0 ? games : n,
      mirrorOpenings: mirror,
      onGame: (g, o, aSeat0) => print(
          '  game ${g + 1}: ${o.winner == null ? "draw${o.capped ? " (ply cap)" : ""}" : "seat ${o.winner} wins"}'
          ' in ${o.plies} plies (A is seat ${aSeat0 ? 0 : 1})'),
    );
    print('$title -> $stats  [${sw.elapsed.inSeconds}s]\n');
  }

  final hard = AiConfig.hard.withTime(hardMs);
  final medium = AiConfig.medium.withTime(hardMs);
  final easy = AiConfig.easy.withTime(easyMs);

  print('== Hard vs Easy ==');
  run('Hard vs Easy', hard, easy);
  print('== Medium vs Easy ==');
  run('Medium vs Easy', medium, easy);
  print('== Hard vs Hard (seat fairness, opening/closing double) ==');
  run('Hard vs Hard', hard, hard, mirror: false);
}
