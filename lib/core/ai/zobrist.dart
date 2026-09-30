import 'dart:math' as math;

import '../engine/engine.dart';

/// Zobrist hashing: every (seat, point) pair, hand size, side to move and
/// placements-left value gets a fixed random 64-bit key; a position's hash is
/// the XOR of the keys that apply to it. Equal positions always hash equal,
/// which is what the transposition table needs.
abstract final class Zobrist {
  static final math.Random _rnd = math.Random(0x5EED5EED);

  // Built with arithmetic, not shifts: on the web ints are JS numbers and
  // `x << 32` would silently wrap, turning every key into 0.
  static int _key() => _rnd.nextInt(0x200000) * 0x80000000 + _rnd.nextInt(0x7FFFFFFF);

  static final List<int> _seat0 = List.generate(Board.pointCount, (_) => _key());
  static final List<int> _seat1 = List.generate(Board.pointCount, (_) => _key());
  static final List<int> _hand0 = List.generate(10, (_) => _key());
  static final List<int> _hand1 = List.generate(10, (_) => _key());
  static final List<int> _places = List.generate(3, (_) => _key());
  static final int _turn = _key();

  static int hash(GameState s) {
    var h = _hand0[s.hand0] ^ _hand1[s.hand1] ^ _places[s.placesLeft];
    if (s.turn == 1) h ^= _turn;
    for (final p in bitsOf(s.mask0)) {
      h ^= _seat0[p];
    }
    for (final p in bitsOf(s.mask1)) {
      h ^= _seat1[p];
    }
    return h;
  }
}
