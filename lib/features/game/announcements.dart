import '../../core/engine/engine.dart';

const _ringNames = ['outer', 'middle', 'inner'];
const _posNames = [
  'top-left corner',
  'top middle',
  'top-right corner',
  'right middle',
  'bottom-right corner',
  'bottom middle',
  'bottom-left corner',
  'left middle',
];

/// "Top-left corner of the outer square" - a spoken name for a board point.
String pointName(int p) =>
    '${_posNames[Board.posOf(p)]} of the ${_ringNames[Board.ringOf(p)]} square';

/// What a screen reader says about one board point.
String pointLabel(
  int p,
  GameState g,
  List<String> names, {
  bool capturable = false,
  bool target = false,
}) {
  final owner = (g.mask0 & bit(p)) != 0 ? 0 : ((g.mask1 & bit(p)) != 0 ? 1 : -1);
  final base = pointName(p);
  if (owner < 0) return '$base, empty${target ? ', you can move here' : ''}';
  final prot = (Rules.protectedMask(g.maskOf(owner)) & bit(p)) != 0 ? ', protected' : '';
  return '$base, ${names[owner]} token$prot${capturable ? ', can be eaten' : ''}';
}

/// One spoken sentence about a move that has just been played.
String announceMove(MoveResult r, List<String> names) {
  final who = names[r.mover];
  final buf = StringBuffer(
    r.move.isPlacement
        ? '$who placed a token on the ${pointName(r.move.to)}.'
        : '$who slid a token to the ${pointName(r.move.to)}.',
  );
  if (r.isMachyas) {
    buf.write(' Machyas! ${names[1 - r.mover]} loses the token on the ${pointName(r.move.capture)}.');
  }
  final swing = r.announcedSwing;
  if (swing != null) {
    final name = swing.call == Call.treghi ? 'Treghi' : 'Begi';
    buf.write(swing.readyOnly ? ' $name ready.' : ' $name!');
  }
  final res = r.after.result;
  if (res != null) {
    buf.write(res.isDraw ? ' The game is a draw.' : ' ${names[res.winner!]} wins.');
  } else {
    buf.write(' ${names[r.after.turn]} to play.');
  }
  return buf.toString();
}
