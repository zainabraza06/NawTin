import '../../core/engine/engine.dart';
import '../setup/game_setup.dart';
import 'game_controller.dart';

/// The text that "Copy game record" puts on the clipboard: the whole game, move
/// by move, in the format `tools/analyze_game.dart` replays.
String gameRecordText(GameUiState ui, GameSetup setup) {
  final meta = <String, String>{
    'mode': setup.mode == GameMode.vsAi ? 'vsAi' : 'friend',
    if (setup.mode == GameMode.vsAi) 'level': setup.difficulty.name,
    if (setup.aiSeat != null) 'ai': '${setup.aiSeat}',
    'rule': Rules.placementRule.name,
    'result': _result(ui.game),
  };
  final moves = [for (final e in ui.history) e.move];
  return GameTranscript(meta, moves).encode();
}

String _result(GameState g) {
  final r = g.result;
  if (r == null) return 'unfinished';
  if (r.isDraw) return 'draw';
  return 'seat${r.winner}wins-${r.reason.name}';
}
