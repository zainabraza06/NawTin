/// The numbers the evaluation uses to judge a position. They live in one vector
/// so they can be tuned by self-play (see tool/tune.dart); [standard] is what
/// the app ships.
///
/// Index order is fixed: [names] lists it.
final class EvalWeights {
  const EvalWeights(this.v);

  final List<int> v;

  static const List<String> names = [
    'material', 'line', 'protect', 'threat', 'double', 'conn', 'swing', 'exposure',
    'connPlace', 'threatPlace', 'swingPlace',
    'mobilityMove', 'blockedMove',
    'materialEnd', 'mobilityEnd', 'blockedEnd', 'connEnd', 'swingEnd',
    'armedTreghi', 'armedBegi', 'progTreghi', 'progBegi', 'onStop',
  ];

  /// The weights the game ships with.
  static const EvalWeights standard = EvalWeights([
    100, 8, 4, 16, 30, 2, 10, 14, //
    4, 20, 14, //
    4, 5, //
    160, 7, 8, 1, 5, //
    260, 120, 5, 8, 12, //
  ]);

  int get material => v[0];
  int get line => v[1];
  int get protect => v[2];
  int get threat => v[3];
  int get doubleThreat => v[4];
  int get conn => v[5];
  int get swing => v[6];
  int get exposure => v[7];
  int get connPlace => v[8];
  int get threatPlace => v[9];
  int get swingPlace => v[10];
  int get mobilityMove => v[11];
  int get blockedMove => v[12];
  int get materialEnd => v[13];
  int get mobilityEnd => v[14];
  int get blockedEnd => v[15];
  int get connEnd => v[16];
  int get swingEnd => v[17];
  int get armedTreghi => v[18];
  int get armedBegi => v[19];
  int get progTreghi => v[20];
  int get progBegi => v[21];
  int get onStop => v[22];

  EvalWeights withValues(List<int> values) {
    assert(values.length == names.length);
    return EvalWeights(List.unmodifiable(values));
  }

  @override
  String toString() => '[${v.join(', ')}]';
}
