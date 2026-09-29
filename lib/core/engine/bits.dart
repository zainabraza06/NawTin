/// Tiny bitmask helpers. The whole board fits in 24 bits (one bit per point),
/// so a set of points is just an `int`.

/// Number of set bits in [x].
int popCount(int x) {
  var n = 0;
  while (x != 0) {
    x &= x - 1; // clears the lowest set bit
    n++;
  }
  return n;
}

/// The single-bit mask for [point].
int bit(int point) => 1 << point;

/// Indices of the set bits of [mask], lowest first.
Iterable<int> bitsOf(int mask) sync* {
  while (mask != 0) {
    final low = mask & -mask; // isolates the lowest set bit
    yield low.bitLength - 1; // its index
    mask ^= low;
  }
}

/// Builds a mask from a list of point indices.
int maskOf(Iterable<int> points) {
  var m = 0;
  for (final p in points) {
    m |= 1 << p;
  }
  return m;
}
