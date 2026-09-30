import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/ai.dart';

/// The AI backend. Runs on a background isolate in the app; tests override it
/// with a [DirectAiService].
final aiServiceProvider = Provider<AiService>((ref) => IsolateAiService());
