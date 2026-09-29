import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/how_to_play/demo_scripts.dart';

/// Replays a script against the real rules and returns each step's result.
List<MoveResult> replay(DemoScript script) {
  var g = script.start;
  final out = <MoveResult>[];
  for (final step in script.steps) {
    expect(Rules.isLegal(g, step.move), isTrue, reason: '${step.move} in $g');
    if (step.pick) {
      expect(Rules.captureTargets(g, step.move.step), isNot(0),
          reason: 'a pick step must complete a line');
    }
    final r = MoveResult.resolve(g, step.move);
    out.add(r);
    g = r.after;
    expect(g.isOver, isFalse, reason: 'demos never end the game');
  }
  return out;
}

void main() {
  test('every demo script is legal and never ends the game', () {
    for (final s in DemoScripts.all) {
      replay(s);
    }
  });

  test('placement demo opens with two tokens for seat 0', () {
    final r = replay(DemoScripts.placement);
    expect(r[0].after.turn, 0);
    expect(r[1].after.turn, 1);
  });

  test('phutas demo sets up a new threat, then pays it off', () {
    final r = replay(DemoScripts.phutas);
    expect(r[0].canPhutas, isTrue);
    expect(r[2].isMachyas, isTrue);
  });

  test('machyas demo: protected line is skipped', () {
    final s = DemoScripts.machyas;
    final targets = Rules.captureTargets(s.start, s.steps.single.move.step);
    expect(targets, maskOf([20, 22]));
    expect(replay(s).single.isMachyas, isTrue);
  });

  test('begi demo announces begi once, then swings are plain machyas', () {
    final r = replay(DemoScripts.begi);
    expect(r[0].announcedSwing!.call, Call.begi);
    expect(r[0].isMachyas, isTrue);
    expect(r[2].isMachyas, isTrue);
    expect(r[2].swingEvents, isEmpty);
    expect(r[2].canPhutas, isFalse);
  });

  test('treghi demo announces treghi once, then swings are plain machyas', () {
    final r = replay(DemoScripts.treghi);
    expect(r[0].announcedSwing!.call, Call.treghi);
    for (final x in r.skip(1)) {
      expect(x.swingEvents, isEmpty);
    }
    expect(r[2].isMachyas, isTrue);
    expect(r[4].isMachyas, isTrue);
  });
}
