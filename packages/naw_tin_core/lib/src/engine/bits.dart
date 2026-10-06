/// Bit helpers for 24-bit board masks.
library;

/// Tiny bitmask helpers. The whole board fits in 24 bits (one bit per point),
/// so a set of points is just an `int`.

/// Number of set bits in [x]. Board masks have at most 24 bits, so a fixed
/// five-step bit-twiddling count (no loop) is used; a value wider than 32 bits
/// falls back to the plain loop.
int popCount(int x) {
  if (x >> 32 != 0 || x < 0) {
    var n = 0;
    while (x != 0) {
      x &= x - 1; // clears the lowest set bit
      n++;
    }
    return n;
  }
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F;
  return ((x * 0x01010101) >> 24) & 0xFF;
}

/// The single-bit mask for [point].
int bit(int point) => 1 << point;

/// Indices of the set bits of [mask], lowest first. (A plain list, built with
/// a loop: a lazy generator here was one of the search's biggest costs.)
List<int> bitsOf(int mask) {
  final out = <int>[];
  while (mask != 0) {
    final low = mask & -mask; // isolates the lowest set bit
    out.add(low.bitLength - 1); // its index
    mask ^= low;
  }
  return out;
}

/// Builds a mask from a list of point indices.
int maskOf(Iterable<int> points) {
  var m = 0;
  for (final p in points) {
    m |= 1 << p;
  }
  return m;
}
