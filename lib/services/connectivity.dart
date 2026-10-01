import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the phone has any network at all (Wi-Fi, mobile data, ...). It only
/// tells "no internet" apart from "the server is down"; it does not prove the
/// internet works. Tests override this provider.
final networkProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool any(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);
  try {
    yield any(await c.checkConnectivity());
    await for (final r in c.onConnectivityChanged) {
      yield any(r);
    }
  } catch (_) {
    yield true; // unknown: assume there is a network, so the server gets the blame
  }
});
