import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:naw_tin_core/naw_tin_core.dart';
import 'package:nawtin/features/online/online_controller.dart';
import 'package:nawtin/features/online/online_messages.dart';
import 'package:nawtin/features/online/online_state.dart';

import 'online_ui_test.dart' show UiRig, connectAs, phone, serverSays, settle;

/// Emotes, reporting and plain-language errors, against the scripted server.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    Rules.placementRule = PlacementRule.symmetricOpening;
  });

  Future<void> startGame(WidgetTester t, UiRig r) async {
    await t.pumpWidget(r.app());
    await connectAs(t, r);
    await serverSays(t, r, r.room(status: 'playing'));
    await serverSays(t, r, r.game(GameState.initial()));
  }

  Future<void> pick(WidgetTester t, String id) async {
    await t.tap(find.bySemanticsLabel('Emotes'));
    await settle(t);
    await t.tap(find.byKey(ValueKey('emote-$id')));
    await settle(t);
  }

  group('emotes', () {
    testWidgets('the picker offers exactly the six presets and no text box', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await t.tap(find.bySemanticsLabel('Emotes'));
      await settle(t);
      for (final id in emoteIds) {
        expect(find.byKey(ValueKey('emote-$id')), findsOneWidget, reason: id);
      }
      expect(find.byType(TextField), findsNothing, reason: 'no free-text chat');
    });

    testWidgets('picking one sends only its preset id', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await pick(t, 'nice_one');
      expect(r.ch.of('emote').single['id'], 'nice_one');
    });

    testWidgets('a second emote within 3 seconds is held back politely, then allowed', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await pick(t, 'nice_one');
      await t.tap(find.bySemanticsLabel('Emotes'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('emote-oops')));
      await settle(t);
      expect(r.ch.of('emote'), hasLength(1), reason: 'nothing sent while cooling down');
      expect(find.textContaining('Easy on the emotes'), findsOneWidget);
      r.clock.advance(const Duration(seconds: 4));
      await t.tap(find.byKey(const ValueKey('emote-oops')));
      await settle(t);
      expect(r.ch.of('emote'), hasLength(2));
    });

    testWidgets('six a minute at most', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      final ctl = ProviderScope.containerOf(t.element(find.byType(MaterialApp))).read(onlineControllerProvider.notifier);
      var sent = 0;
      for (var i = 0; i < 10; i++) {
        if (ctl.emote('thanks')) sent++;
        r.clock.advance(const Duration(seconds: 3, milliseconds: 100));
      }
      expect(sent, 6);
      r.clock.advance(const Duration(seconds: 40));
      expect(ctl.emote('thanks'), isTrue, reason: 'the minute rolled over');
    });

    testWidgets('an emote from the friend shows as a bubble for a moment', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await serverSays(t, r, {'t': 'event', 'rev': 5, 'kind': 'emote', 'seat': 1, 'data': {'seat': 1, 'id': 'good_game'}});
      expect(find.text('Good game'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      expect(find.text('Good game'), findsNothing);
    });

    testWidgets('an unknown id in an emote event is ignored (no free text can arrive)', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await serverSays(t, r, {'t': 'event', 'rev': 5, 'kind': 'emote', 'seat': 1, 'data': {'seat': 1, 'id': 'buy my stuff at example.com'}});
      expect(find.textContaining('example.com'), findsNothing);
    });

    testWidgets('Hide emotes removes the button and silences incoming ones', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await t.tap(find.bySemanticsLabel('Emotes'));
      await settle(t);
      await t.tap(find.text('Hide emotes'));
      await settle(t);
      expect(find.bySemanticsLabel('Emotes'), findsNothing);
      await serverSays(t, r, {'t': 'event', 'rev': 5, 'kind': 'emote', 'seat': 1, 'data': {'seat': 1, 'id': 'good_game'}});
      expect(find.text('Good game'), findsNothing);
      expect(r.store.read('online.hideEmotes'), '1', reason: 'remembered on the device');
    });

    testWidgets('if the server still rate-limits, the player reads a friendly sentence', (t) async {
      phone(t);
      final r = UiRig();
      await startGame(t, r);
      await serverSays(t, r, {'t': 'error', 'code': 'rate_limited', 'message': 'Easy on the emotes.', 'retryAfterMs': 3000});
      expect(find.textContaining("You're going a little fast. Try again in 3 seconds."), findsOneWidget);
    });
  });

  group('reporting', () {
    Future<void> gameOver(WidgetTester t, UiRig r) async {
      await startGame(t, r);
      await serverSays(t, r, r.room(status: 'finished'));
      await serverSays(t, r, r.game(GameState.initial().disqualify(1)));
    }

    testWidgets('after a game you can report the other player for a fixed reason, once', (t) async {
      phone(t);
      final r = UiRig();
      await gameOver(t, r);
      await t.tap(find.byKey(const ValueKey('report-button')));
      await settle(t);
      expect(find.byType(TextField), findsNothing, reason: 'reasons are a fixed list, never free text');
      await t.tap(find.byKey(const ValueKey('report-abusive_name')));
      await settle(t);
      final sent = r.ch.of('report').single;
      expect(sent['userId'], 'opp');
      expect(sent['reason'], 'abusive_name');
      expect(find.text('Reported'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('report-button')), warnIfMissed: false);
      await settle(t);
      expect(r.ch.of('report'), hasLength(1));
    });

    testWidgets('cancelling the sheet sends nothing', (t) async {
      phone(t);
      final r = UiRig();
      await gameOver(t, r);
      await t.tap(find.byKey(const ValueKey('report-button')));
      await settle(t);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(r.ch.of('report'), isEmpty);
      expect(find.text('Report Sara'), findsOneWidget);
    });
  });

  group('messages', () {
    test('every error code the app can meet has a plain sentence, never a code', () {
      for (final code in [
        ErrorCodes.rateLimited, ErrorCodes.roomNotFound, ErrorCodes.roomFull, ErrorCodes.roomExpired, ErrorCodes.roomClosed,
        ErrorCodes.alreadyInRoom, ErrorCodes.notInRoom, ErrorCodes.notYourTurn, ErrorCodes.illegalMove, ErrorCodes.illegalCapture,
        ErrorCodes.capturePending, ErrorCodes.notHost, ErrorCodes.notReady, ErrorCodes.nameInvalid, ErrorCodes.rematchUnavailable,
        ErrorCodes.serverBusy, ErrorCodes.internal, 'something_new', 'not_connected',
      ]) {
        final text = errorText(OnlineError(code, 'raw server words'));
        expect(text, isNotEmpty, reason: code);
        expect(text, isNot(contains('_')), reason: '$code leaks a code: $text');
        expect(text, isNot(contains('raw server words')));
      }
    });

    test('waits are said the way people say them', () {
      expect(waitText(3000), 'in 3 seconds');
      expect(waitText(1000), 'in 1 second');
      expect(waitText(10 * 60 * 1000), 'in 10 minutes');
      expect(waitText(null), 'in a moment');
      expect(errorText(const OnlineError(ErrorCodes.rateLimited, 'x', retryAfterMs: 600000)), contains('in 10 minutes'));
    });
  });

  group('no ads in a live online game', () {
    test('nothing under the online feature touches the ads service', () {
      final files = Directory('lib/features/online')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final src = f.readAsStringSync();
        expect(src.contains('services/ads'), isFalse, reason: f.path);
        expect(src.contains('ad_gate'), isFalse, reason: f.path);
        expect(src.contains('google_mobile_ads'), isFalse, reason: f.path);
      }
    });
  });
}
