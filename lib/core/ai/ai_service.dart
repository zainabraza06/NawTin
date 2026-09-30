import 'dart:isolate';

import '../engine/engine.dart';
import 'ai_config.dart';
import 'searcher.dart';

/// Picks a move for the side to move. The app uses [IsolateAiService] so the
/// UI never freezes; tests and the self-play harness use [DirectAiService].
abstract class AiService {
  Future<SearchResult> search(GameState state, AiConfig config);

  Future<Move> chooseMove(GameState state, AiConfig config) async =>
      (await search(state, config)).move;
}

final class _Job {
  const _Job(this.state, this.config);
  final GameState state;
  final AiConfig config;
}

SearchResult _run(_Job job) => Searcher(job.config).search(job.state);

/// Runs the search on a background isolate.
class IsolateAiService extends AiService {
  @override
  Future<SearchResult> search(GameState state, AiConfig config) {
    final job = _Job(state, config);
    return Isolate.run(() => _run(job));
  }
}

/// Runs the search on the calling isolate (deterministic, test friendly).
class DirectAiService extends AiService {
  @override
  Future<SearchResult> search(GameState state, AiConfig config) async =>
      _run(_Job(state, config));
}
