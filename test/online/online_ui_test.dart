import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:naw_tin_server/naw_tin_server.dart' as srv;
import 'package:nawtin/app_router.dart';
import 'package:nawtin/features/online/online_controller.dart';
import 'package:nawtin/features/online/online_issue.dart';
import 'package:nawtin/features/online/screens/lobby_view.dart';
import 'package:nawtin/services/connectivity.dart';
import 'package:nawtin/services/online/online_config.dart';
import 'package:nawtin/services/online/online_service.dart';
import 'package:nawtin/services/prefs_store.dart';
import 'package:nawtin/theme/app_theme.dart';
import 'package:nawtin/widgets/board_view.dart';

import 'support.dart';

/// The whole online UI against a scripted server (no sockets, no timers that
/// matter): what the player sees for each situation.
class UiRig {
  UiRig({this.stored, this.network = true})
      : clock = srv.FakeClock(),
        transport = ScriptedTransport(),
        store = MemoryPrefsStore() {
    if (stored != null) store.write('online.room', stored!);
  }

  final String? stored;
  final bool network;
  final srv.FakeClock clock;
  final ScriptedTransport transport;
  final MemoryPrefsStore store;
  ScriptedChannel get ch => transport.last;

  Widget app({String initial = Routes.online, Object? args}) => ProviderScope(
        overrides: [
          prefsStoreProvider.overrideWithValue(store),
          onlineConfigProvider.overrideWithValue(OnlineConfig.parse('ws://localhost:8080/ws', release: false)),
          onlineTransportProvider.overrideWithValue(transport),
          onlineSchedulerProvider.overrideWithValue(ClockScheduler(clock)),
          networkProvider.overrideWith((ref) => Stream.value(network)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          onGenerateRoute: (settings) => onGenerateRoute(settings.name == '/' ? RouteSettings(name: initial, arguments: args) : settings),
          initialRoute: '/',
        ),
      );

  Map<String, Object?> room({
    String status = 'lobby',
    String code = 'K7TQ3M',
    bool oppReady = true,
    bool oppConnected = true,
    bool withOpponent = true,
    String host = 'me',
    String? rematchBy,
    int mySeat = 0,
  }) {
    final seated = status == 'playing' || status == 'finished';
    return {
      't': 'room_state',
      'code': code,
      'status': status,
      'expiresAt': clock.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      'host': host,
      'players': [
        {'userId': 'me', 'name': 'Zainab', 'avatar': 1, 'connected': true, 'ready': true, 'seat': seated ? mySeat : null, 'pingMs': 30, 'lastSeq': 0},
        if (withOpponent)
          {'userId': 'opp', 'name': 'Sara', 'avatar': 2, 'connected': oppConnected, 'ready': oppReady, 'seat': seated ? 1 - mySeat : null, 'pingMs': 50, 'lastSeq': 0},
      ],
      'rules': {'placementRule': 'symmetricOpening', 'turnSeconds': 120, 'reconnectSeconds': 45},
      'coinFlip': status == 'lobby' ? null : {'seat0': mySeat == 0 ? 'me' : 'opp'},
      'rematch': {'offeredBy': rematchBy},
      'rev': 1,
    };
  }

  Map<String, Object?> game(GameState g, {int clockSeat = 0}) => {
        't': 'game_state',
        'rev': 2,
        'ts': clock.now().millisecondsSinceEpoch,
        'snapshot': encodeSnapshot(g),
        'pending': null,
        'clock': {'seat': clockSeat, 'deadline': clock.now().millisecondsSinceEpoch + 90000, 'totalMs': 120000, 'graceMs': 1500},
        'timeouts': [0, 0],
        'stats': {'eaten': [2, 1], 'lines': [1, 0], 'swings': [0, 0]},
        'phutas': null,
        'lastMove': null,
      };
}

/// Lets queued futures (the scripted socket) and the UI catch up.
Future<void> settle(WidgetTester t) async {
  await t.runAsync(() => pump(12));
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> serverSays(WidgetTester t, UiRig r, Map<String, Object?> m) async {
  r.ch.serverSend(m);
  await settle(t);
}

Future<void> connectAs(WidgetTester t, UiRig r, {Map<String, Object?>? resume}) async {
  await settle(t); // post-frame connect
  r.ch.serverSend({
    't': 'welcome',
    'ts': r.clock.now().millisecondsSinceEpoch,
    'userId': 'me',
    if (resume != null) 'resume': resume,
  });
  await settle(t);
}

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2280);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    Rules.placementRule = PlacementRule.symmetricOpening;
  });

  group('which problem screen is shown', () {
    ConnectionState c(ConnPhase p, {Problem? problem, int attempt = 0, StopReason? stop}) =>
        ConnectionState(p, problem: problem, attempt: attempt, stopReason: stop);

    test('hard stops each have their own screen', () {
      expect(issueFor(c(ConnPhase.stopped, stop: StopReason.outdated), hasNetwork: true), OnlineIssue.outdated);
      expect(issueFor(c(ConnPhase.stopped, stop: StopReason.replaced), hasNetwork: true), OnlineIssue.replaced);
      expect(issueFor(c(ConnPhase.stopped, stop: StopReason.unauthorized), hasNetwork: true), OnlineIssue.signInFailed);
      expect(issueFor(c(ConnPhase.stopped, stop: StopReason.authUnavailable), hasNetwork: true), OnlineIssue.signInFailed);
      expect(issueFor(c(ConnPhase.stopped, stop: StopReason.notConfigured), hasNetwork: true), OnlineIssue.notConfigured);
    });

    test('no internet is told apart from a server that is down', () {
      final failing = c(ConnPhase.reconnecting, problem: Problem.unreachable, attempt: 3);
      expect(issueFor(failing, hasNetwork: false), OnlineIssue.noInternet);
      expect(issueFor(failing, hasNetwork: true), OnlineIssue.serverDown);
    });

    test('the first hiccups are just "connecting", and a healthy connection has no issue', () {
      expect(issueFor(c(ConnPhase.connecting, attempt: 0), hasNetwork: true), isNull);
      expect(issueFor(c(ConnPhase.reconnecting, problem: Problem.unreachable, attempt: 1), hasNetwork: true), isNull);
      expect(issueFor(c(ConnPhase.online), hasNetwork: true), isNull);
    });

    test('every problem has one clear message and one action', () {
      for (final i in OnlineIssue.values) {
        final copy = issueCopy[i]!;
        expect(copy.title, isNotEmpty);
        expect(copy.message, isNotEmpty);
        expect(copy.actionLabel, isNotEmpty);
      }
      expect(issueCopy[OnlineIssue.replaced]!.title, 'Naw Tin is open somewhere else');
      expect(issueCopy[OnlineIssue.outdated]!.title, 'Please update the app');
    });
  });

  group('menu', () {
    testWidgets('connects, then Create room asks the server for a room', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      expect(find.text('Create a room'), findsOneWidget);
      await t.tap(find.text('Create a room'));
      await settle(t);
      expect(r.ch.of('create_room'), hasLength(1));
    });

    testWidgets('before the connection is up the buttons are disabled and say so', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await settle(t);
      await t.tap(find.text('Create a room'));
      await settle(t);
      expect(r.transport.channels.every((ch) => ch.of('create_room').isEmpty), isTrue);
      expect(find.text('Connecting...'), findsWidgets);
    });

    testWidgets('an outdated app gets the update screen, not a spinner', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await settle(t);
      r.ch.serverClose(4000);
      await settle(t);
      expect(find.text('Please update the app'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('"open somewhere else" is a friendly screen with a way back in', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      r.ch.serverClose(4002);
      await settle(t);
      expect(find.text('Naw Tin is open somewhere else'), findsOneWidget);
      expect(find.text('Use it here'), findsOneWidget);
    });

    testWidgets('no network shows "No internet connection" with a retry', (t) async {
      phone(t);
      final r = UiRig(network: false);
      r.transport.failWith = Exception('unreachable');
      await t.pumpWidget(r.app());
      for (var i = 0; i < 12; i++) {
        await t.runAsync(() => pump(6));
        r.clock.advance(const Duration(seconds: 2));
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('network on but the server not answering says the server is the problem', (t) async {
      phone(t);
      final r = UiRig(network: true);
      r.transport.failWith = Exception('refused');
      await t.pumpWidget(r.app());
      for (var i = 0; i < 12; i++) {
        await t.runAsync(() => pump(6));
        r.clock.advance(const Duration(seconds: 2));
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.text("Can't reach the game server"), findsOneWidget);
    });
  });

  group('join', () {
    testWidgets('typing a code, with lower case and a dash, joins with the clean code', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await t.tap(find.text('Join with a code'));
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('code-input')), 'k7t-q3m');
      await t.pump();
      await t.tap(find.text('Join').last);
      await settle(t);
      expect(r.ch.of('join_room').single['code'], 'K7TQ3M');
    });

    testWidgets('Join stays disabled until all six symbols are in', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await t.tap(find.text('Join with a code'));
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('code-input')), 'K7T');
      await t.pump();
      await t.tap(find.text('Join').last);
      await settle(t);
      expect(r.ch.of('join_room'), isEmpty);
    });

    testWidgets('an unknown code explains itself in plain words', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await t.tap(find.text('Join with a code'));
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('code-input')), 'ZZZZZZ');
      await t.tap(find.text('Join').last);
      await settle(t);
      await serverSays(t, r, {'t': 'error', 'code': 'room_not_found', 'message': 'No such room'});
      expect(find.textContaining("couldn't find a game with that code"), findsOneWidget);
    });

    testWidgets('a full room and an expired room each say so', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await t.tap(find.text('Join with a code'));
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('code-input')), 'K7TQ3M');
      await t.tap(find.text('Join').last);
      await settle(t);
      await serverSays(t, r, {'t': 'error', 'code': 'room_full', 'message': 'full'});
      expect(find.text('That game already has two players.'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('code-input')), 'K7TQ3N');
      await t.tap(find.text('Join').last);
      await settle(t);
      await serverSays(t, r, {'t': 'error', 'code': 'room_expired', 'message': 'old'});
      expect(find.textContaining('has expired'), findsOneWidget);
    });

    testWidgets('a code on the clipboard is offered as a one-tap paste', (t) async {
      phone(t);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': 'Play Naw Tin with me! enter: K7TQ3M'};
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await t.tap(find.text('Join with a code'));
      await settle(t);
      expect(find.text('Paste K7TQ3M'), findsOneWidget);
      await t.tap(find.text('Paste K7TQ3M'));
      await t.pump();
      await t.tap(find.text('Join').last);
      await settle(t);
      expect(r.ch.of('join_room').single['code'], 'K7TQ3M');
    });

    testWidgets('once the server puts us in the room the join page gives way to the lobby', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await t.tap(find.text('Join with a code'));
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('code-input')), 'K7TQ3M');
      await t.tap(find.text('Join').last);
      await settle(t);
      await serverSays(t, r, r.room(host: 'opp'));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Your room'), findsOneWidget);
      expect(find.text('Join a game'), findsNothing);
    });
  });

  group('lobby', () {
    testWidgets('shows the code, who is here, and a share message with the code in it', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await serverSays(t, r, r.room(withOpponent: false));
      expect(find.text('K7TQ3M'), findsOneWidget);
      expect(find.text('Waiting for your friend...'), findsOneWidget);
      expect(shareMessage('K7TQ3M'), contains('K7TQ3M'));
      expect(shareMessage('K7TQ3M'), contains('Join with a code'));
    });

    testWidgets('the host can only start once the friend is ready', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await serverSays(t, r, r.room(oppReady: false));
      await t.tap(find.text('Start game'));
      await settle(t);
      expect(r.ch.of('start'), isEmpty);
      expect(find.text('Waiting for your friend to get ready'), findsOneWidget);
      await serverSays(t, r, r.room(oppReady: true));
      await t.tap(find.text('Start game'));
      await settle(t);
      expect(r.ch.of('start'), hasLength(1));
    });

    testWidgets('a guest gets a ready toggle, not a start button', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await serverSays(t, r, r.room(host: 'opp'));
      expect(find.text('Start game'), findsNothing);
      await t.tap(find.text('Not ready')); // our player is already shown ready by the server fixture
      await settle(t);
      expect(r.ch.of('ready').single['ready'], false);
    });

    testWidgets('leaving the lobby asks first, then sends leave', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await serverSays(t, r, r.room());
      await t.tap(find.text('Leave room'));
      await settle(t);
      expect(find.text('Leave this room?'), findsOneWidget);
      await t.tap(find.text('Stay'));
      await settle(t);
      expect(r.ch.of('leave'), isEmpty);
      await t.tap(find.text('Leave room'));
      await settle(t);
      await t.tap(find.text('Leave').last);
      await settle(t);
      expect(r.ch.of('leave'), hasLength(1));
      expect(find.text('Create a room'), findsOneWidget, reason: 'back at the menu');
    });
  });

  group('game', () {
    Future<void> startGame(WidgetTester t, UiRig r, {GameState? state, int mySeat = 0}) async {
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await serverSays(t, r, r.room(status: 'playing', mySeat: mySeat));
      await serverSays(t, r, r.game(state ?? GameState.initial(), clockSeat: 0));
    }

    testWidgets('shows the real board, both players, the clock and whose turn it is', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      expect(find.byType(BoardView), findsOneWidget);
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('Zainab (you)'), findsOneWidget);
      expect(find.text('YOUR TURN'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget, reason: 'the deadline is 90 s away');
    });

    testWidgets('no hints and no rewind online: only PHUTAS and Leave', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      expect(find.text('Hint'), findsNothing);
      expect(find.text('Rewind'), findsNothing);
      expect(find.text('PHUTAS'), findsOneWidget);
      expect(find.bySemanticsLabel('Leave game'), findsOneWidget);
    });

    testWidgets('the leave button opens the confirmation; only Leave sends leave', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await t.tap(find.byIcon(Icons.exit_to_app_rounded));
      await settle(t);
      expect(find.text('Leave the game?'), findsOneWidget);
      expect(find.text('You will forfeit and your opponent wins.'), findsOneWidget);
      await t.tap(find.text('Stay'));
      await settle(t);
      expect(r.ch.of('leave'), isEmpty);
      await t.tap(find.byIcon(Icons.exit_to_app_rounded));
      await settle(t);
      await t.tap(find.text('Leave').last);
      await settle(t);
      expect(r.ch.of('leave'), hasLength(1));
    });

    testWidgets('the system back button also asks before forfeiting', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.text('Leave the game?'), findsOneWidget);
      expect(r.ch.of('leave'), isEmpty);
    });

    testWidgets('tapping a point on my turn places a token (the server decides)', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      final board = t.getRect(find.byType(BoardView));
      await t.tapAt(board.center);
      await settle(t);
      // something near the centre was tapped: either a place was sent or the tap missed a point;
      // tap the four corners to be sure at least one lands on a point
      for (final o in [board.topLeft + const Offset(20, 20), board.topRight + const Offset(-20, 20), board.bottomLeft + const Offset(20, -20)]) {
        await t.tapAt(o);
        await settle(t);
      }
      expect(r.ch.of('place'), isNotEmpty);
    });

    testWidgets('when it is not my turn, taps send nothing', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app());
      await connectAs(t, r);
      await serverSays(t, r, r.room(status: 'playing', mySeat: 1));
      await serverSays(t, r, r.game(GameState.initial(), clockSeat: 0));
      expect(find.text('THEIR TURN'), findsOneWidget);
      final board = t.getRect(find.byType(BoardView));
      for (final o in [board.topLeft + const Offset(20, 20), board.topRight + const Offset(-20, 20), board.center]) {
        await t.tapAt(o);
        await settle(t);
      }
      expect(r.ch.of('place'), isEmpty);
    });

    testWidgets('while the opponent is away a banner counts down and the game is held, not forfeited', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await serverSays(t, r, {
        't': 'event',
        'rev': 3,
        'kind': 'disconnected',
        'seat': 1,
        'data': {'reconnectDeadline': r.clock.now().millisecondsSinceEpoch + 45000},
      });
      expect(find.textContaining('Sara lost connection'), findsOneWidget);
      expect(r.ch.of('leave'), isEmpty);
      await serverSays(t, r, {'t': 'event', 'rev': 4, 'kind': 'reconnected', 'seat': 1, 'data': {}});
      expect(find.textContaining('lost connection'), findsNothing);
    });

    testWidgets('losing my own connection keeps the board and shows a reconnecting banner', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      r.ch.networkDrop();
      await settle(t);
      expect(find.byType(BoardView), findsOneWidget);
      expect(find.textContaining('Reconnecting'), findsOneWidget);
      expect(r.ch.of('leave'), isEmpty);
    });

    testWidgets('game over shows the winner, why, stats, and a rematch that waits for the friend', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      final over = GameState.initial().disqualify(1); // seat 1 loses, so seat 0 (me) wins
      await serverSays(t, r, r.room(status: 'finished'));
      await serverSays(t, r, r.game(over));
      expect(find.text('YOU WIN'), findsWidgets);
      expect(find.text('Rematch'), findsOneWidget);
      await t.tap(find.text('Rematch'));
      await settle(t);
      expect(r.ch.of('offer_rematch'), hasLength(1));
      await serverSays(t, r, r.room(status: 'finished', rematchBy: 'me'));
      expect(find.text('Waiting for Sara...'), findsOneWidget);
    });

    testWidgets('when the friend offers a rematch the button becomes Accept', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await serverSays(t, r, r.room(status: 'finished', rematchBy: 'opp'));
      await serverSays(t, r, r.game(GameState.initial().disqualify(0)));
      expect(find.text('Accept rematch'), findsOneWidget);
      await t.tap(find.text('Accept rematch'));
      await settle(t);
      expect(r.ch.of('accept_rematch'), hasLength(1));
    });

    testWidgets('a forfeit by the friend is explained', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      final over = GameState.initial().disqualify(1);
      await serverSays(t, r, r.room(status: 'finished'));
      final m = r.game(over);
      m['snapshot'] = encodeSnapshot(over, endReasonOverride: 'forfeit');
      await serverSays(t, r, m);
      expect(find.text('Sara left the game.'), findsOneWidget);
    });
  });

  group('home', () {
    testWidgets('a saved game shows a rejoin card; Rejoin reconnects and rejoins it', (t) async {
      phone(t);
      final r = UiRig(stored: 'K7TQ3M');
      await t.pumpWidget(r.app(initial: Routes.home));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Game in progress'), findsOneWidget);
      expect(find.text('Room K7TQ3M'), findsOneWidget);
      await t.tap(find.text('Rejoin'));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 800));
      await settle(t);
      r.ch.serverSend({'t': 'welcome', 'ts': r.clock.now().millisecondsSinceEpoch, 'userId': 'me', 'resume': {'code': 'K7TQ3M', 'status': 'playing'}});
      await settle(t);
      expect(r.ch.of('join_room').single['code'], 'K7TQ3M');
    });

    testWidgets('no saved game, no card; Play Online is on the home screen', (t) async {
      phone(t);
      final r = UiRig();
      await t.pumpWidget(r.app(initial: Routes.home));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Game in progress'), findsNothing);
      expect(find.text('Play Online'), findsOneWidget);
    });

    testWidgets('removing a saved game that is already gone just clears the card', (t) async {
      phone(t);
      final r = UiRig(stored: 'K7TQ3M');
      await t.pumpWidget(r.app(initial: Routes.home));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.byTooltip('Remove this game'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Remove this game?'), findsOneWidget);
      await t.tap(find.text('Remove'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Game in progress'), findsNothing);
      expect(r.store.read('online.room'), '');
    });

    testWidgets('rejoining a room that no longer exists says so and clears the saved game', (t) async {
      phone(t);
      final r = UiRig(stored: 'K7TQ3M');
      await t.pumpWidget(r.app(initial: Routes.online, args: true));
      await connectAs(t, r, resume: {'code': 'K7TQ3M', 'status': 'playing'});
      await serverSays(t, r, {'t': 'error', 'code': 'room_not_found', 'message': 'gone'});
      expect(find.text('No game with that code'), findsOneWidget);
      expect(r.store.read('online.room'), '');
    });
  });
}
