# naw_tin_core

The pure-Dart heart of Naw Tin, shared by the Flutter app and the online server.

* `lib/src/engine/` - board data (24 points, 16 lines, adjacency), the 48
  begi/treghi patterns as bitmasks, immutable `GameState`, move generation,
  captures, protection, win/draw detection, call analysis (Phutas, Machyas,
  Begi, Treghi), and the `PlacementRule` switch.
* `lib/src/ai/` - negamax with alpha-beta, iterative deepening, Zobrist
  transposition table, the hint analyzer and the self-play harness.

It has **no dependencies** besides `dart:math` and `dart:isolate`: no Flutter,
no Riverpod, no network or file I/O.

```
cd packages/naw_tin_core
dart pub get
dart test
```

Import it with `import 'package:naw_tin_core/naw_tin_core.dart';`.
