import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/ai.dart';

/// The AI backend. Runs on a background isolate in the app; tests override it
/// with a [DirectAiService].
/// Web has no isolates (`Isolate.run` is unsupported), so there the search runs
/// on the main thread; the controller shortens the time cap to keep it smooth.
final aiServiceProvider = Provider<AiService>(
  (ref) => kIsWeb ? DirectAiService() : IsolateAiService(),
);
