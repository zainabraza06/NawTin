import 'package:flutter/material.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

import 'online_state.dart';

/// "in 8 seconds" / "in 4 minutes" for a wait the server asked for.
String waitText(int? ms) {
  if (ms == null || ms <= 0) return 'in a moment';
  final s = (ms / 1000).ceil();
  if (s < 90) return 'in $s second${s == 1 ? '' : 's'}';
  final m = (s / 60).ceil();
  return 'in $m minutes';
}

/// Plain-language text for a server error. Players never see error codes or
/// the server's wording; every code the app can meet has a sentence here.
String errorText(OnlineError e) {
  switch (e.code) {
    case ErrorCodes.rateLimited:
      return "You're going a little fast. Try again ${waitText(e.retryAfterMs)}.";
    case ErrorCodes.roomNotFound:
      return "We couldn't find a game with that code.";
    case ErrorCodes.roomFull:
      return 'That game already has two players.';
    case ErrorCodes.roomExpired:
      return 'That room has expired. Ask your friend for a new code.';
    case ErrorCodes.roomClosed:
      return 'That room is closed.';
    case ErrorCodes.alreadyInRoom:
      return "You're already in a game. Rejoin it from the home screen.";
    case ErrorCodes.notInRoom:
      return "You're not in a room any more.";
    case ErrorCodes.notYourTurn:
      return "It's not your turn.";
    case ErrorCodes.illegalMove:
    case ErrorCodes.wrongPhase:
    case ErrorCodes.gameNotActive:
      return "That move isn't allowed.";
    case ErrorCodes.illegalCapture:
    case ErrorCodes.capturePending:
    case ErrorCodes.noCapturePending:
      return 'Pick one of the glowing tokens to eat.';
    case ErrorCodes.notHost:
      return 'Only the host can start the game.';
    case ErrorCodes.notReady:
      return "Your friend isn't ready yet.";
    case ErrorCodes.nameInvalid:
      return 'Please pick another name.';
    case ErrorCodes.rematchUnavailable:
      return "A rematch isn't available right now.";
    case ErrorCodes.serverBusy:
      return 'The server is busy. Try again in a moment.';
    case ErrorCodes.unauthorized:
      return "We couldn't sign you in.";
    case ErrorCodes.unsupportedVersion:
      return 'Please update the app to play online.';
    case 'not_connected':
      return "You're not connected to the server yet.";
    default:
      return 'Something went wrong. Please try again.';
  }
}

/// The six preset emotes: the only way players talk during a game.
class EmoteSpec {
  const EmoteSpec(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const emoteSpecs = <EmoteSpec>[
  EmoteSpec('machyas', 'Machyas!', Icons.local_fire_department_rounded),
  EmoteSpec('nice_one', 'Nice one', Icons.thumb_up_alt_rounded),
  EmoteSpec('oops', 'Oops', Icons.sentiment_dissatisfied_rounded),
  EmoteSpec('good_game', 'Good game', Icons.handshake_rounded),
  EmoteSpec('thinking', 'Hmm...', Icons.psychology_alt_rounded),
  EmoteSpec('thanks', 'Thanks', Icons.favorite_rounded),
];

EmoteSpec? emoteSpec(String id) {
  for (final e in emoteSpecs) {
    if (e.id == id) return e;
  }
  return null;
}

/// Reasons offered when reporting the other player (same ids the server accepts).
class ReportReason {
  const ReportReason(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;
}

const reportReasons = <ReportReason>[
  ReportReason('afk', 'Not playing', 'They left the game open and did not move.'),
  ReportReason('abusive_name', 'Offensive name', 'Their display name is rude or inappropriate.'),
  ReportReason('cheating', 'Cheating', 'They seem to be using something unfair.'),
  ReportReason('other', 'Something else', 'Another problem with this player.'),
];
