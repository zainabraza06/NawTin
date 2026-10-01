import 'dart:math';

/// Display-name validation: 2-16 characters, letters / digits / space / `_` /
/// `-`, single spaces only, and a profanity filter that sees through common
/// look-alike substitutions (0 for o, 1 for i, 3 for e, $ for s ...).
///
/// The list below is deliberately short and obvious; extend it as needed.
const _blocked = [
  'fuck', 'shit', 'bitch', 'cunt', 'dick', 'cock', 'pussy', 'slut', 'whore',
  'bastard', 'asshole', 'nigg', 'fagg', 'retard', 'rape', 'nazi', 'hitler',
  'porn', 'sex', 'penis', 'vagina', 'boob', 'kill yourself', 'kys',
  'admin', 'moderator', 'naw tin', 'nawtin',
];

final _allowed = RegExp(r'^[A-Za-z0-9 _-]+$');

String _normalise(String s) {
  const map = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b'};
  final lower = s.toLowerCase().replaceAll('\$', 's').replaceAll('@', 'a');
  final b = StringBuffer();
  for (final c in lower.split('')) {
    b.write(map[c] ?? c);
  }
  // drop separators so "f u c k" or "f_u_c_k" is seen as one word
  return b.toString().replaceAll(RegExp(r'[ _-]'), '');
}

/// Returns the cleaned name, or null when it is not acceptable.
String? validateName(String? raw) {
  if (raw == null) return null;
  final name = raw.trim().replaceAll(RegExp(r' {2,}'), ' ');
  if (name.length < 2 || name.length > 16) return null;
  if (!_allowed.hasMatch(name)) return null;
  final flat = _normalise(name);
  final flatSpaced = name.toLowerCase();
  for (final bad in _blocked) {
    final b = _normalise(bad);
    if (flat.contains(b) || flatSpaced.contains(bad)) return null;
  }
  return name;
}

const _adjectives = [
  'Swift', 'Brave', 'Lucky', 'Calm', 'Bright', 'Clever', 'Cosmic', 'Neon', 'Quiet', 'Bold',
  'Sunny', 'Misty', 'Royal', 'Rapid', 'Sharp', 'Gentle', 'Golden', 'Lively', 'Witty', 'Noble',
];
const _animals = [
  'Otter', 'Falcon', 'Panda', 'Tiger', 'Heron', 'Lynx', 'Koala', 'Gecko', 'Raven', 'Dolphin',
  'Bison', 'Fox', 'Owl', 'Whale', 'Eagle', 'Moose', 'Cobra', 'Crane', 'Newt', 'Yak',
];

/// A friendly default display name such as "SwiftOtter" (always valid).
String generateName(Random random) =>
    '${_adjectives[random.nextInt(_adjectives.length)]}${_animals[random.nextInt(_animals.length)]}';
