import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nawtin/core/engine/engine.dart';
import 'package:nawtin/features/game/game_controller.dart';
import 'package:nawtin/features/game/game_over_overlay.dart';
import 'package:nawtin/features/game/game_record_text.dart';
import 'package:nawtin/features/setup/game_setup.dart';
import 'package:nawtin/theme/app_theme.dart';

/// Plays [moves] from the start, keeping the history the way the controller does.
GameUiState played(List<Move> moves) {
  var ui = GameUiState.initial(const ['You', 'Naw Bot']);
  for (final m in moves) {
    ui = ui.copyWith(
      history: [...ui.history, HistoryEntry(ui.game, ui.eaten, ui.linesFormed, ui.swings, m)],
      game: Rules.apply(ui.game, m),
    );
  }
  return ui;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    Rules.placementRule = PlacementRule.symmetricOpening;
  });

  test('the record names the level, the AI seat and every move, and replays to the same game', () {
    final moves = <Move>[const Move.place(16), const Move.place(5), const Move.place(14), const Move.place(7)];
    final ui = played(moves);
    const setup = GameSetup(difficulty: Difficulty.hard);
    final text = gameRecordText(ui, setup);

    expect(text, startsWith('NAWTIN1 mode=vsAi level=hard ai=1 rule=symmetricOpening'));
    final rec = GameTranscript.parse(text)!;
    expect(rec.meta['level'], 'hard');
    expect(rec.meta['ai'], '1');
    expect(rec.moves, moves);
    expect(rec.positions().last, ui.game);
  });

  test('a rewound game gives a shorter record (the history is the record)', () {
    final ui = played([const Move.place(1), const Move.place(2), const Move.place(3)]);
    final rewound = ui.copyWith(history: ui.history.sublist(0, 1));
    expect(GameTranscript.parse(gameRecordText(rewound, const GameSetup()))!.moves.length, 1);
  });

  test('two players on one phone are recorded as a friend game, without an AI seat', () {
    final text = gameRecordText(played([const Move.place(0)]), const GameSetup(mode: GameMode.friend));
    final rec = GameTranscript.parse(text)!;
    expect(rec.meta['mode'], 'friend');
    expect(rec.meta.containsKey('ai'), isFalse);
  });

  testWidgets('"Copy game record" puts the record on the clipboard', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final ui = GameUiState.initial(const ['You', 'Naw Bot']).copyWith(game: GameState.initial().disqualify(1));
    const record = 'NAWTIN1 mode=vsAi level=hard ai=1 rule=symmetricOpening\np9 p12';
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: GameOverOverlay(ui: ui, record: record, onRematch: () {}, onChangeMode: () {}, onHome: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('copy-record')));
    await t.pump(const Duration(milliseconds: 300));
    expect(copied, record);
    expect(find.textContaining('Game record copied'), findsOneWidget);
  });

  testWidgets('without a record there is no copy button (online games, tests)', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final ui = GameUiState.initial(const ['You', 'Naw Bot']).copyWith(game: GameState.initial().disqualify(1));
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: GameOverOverlay(ui: ui, onRematch: () {}, onChangeMode: () {}, onHome: () {})),
    ));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('copy-record')), findsNothing);
  });
}
