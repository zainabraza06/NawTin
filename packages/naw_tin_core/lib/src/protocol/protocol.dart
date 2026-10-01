/// Constants shared by the online server and the app (see docs/online_protocol.md).
library;

/// The protocol version this build speaks.
const int protocolVersion = 1;

/// The oldest protocol the server still serves.
const int minProtocolVersion = 1;

/// Room codes: 6 characters, no 0 / O / 1 / I (easy to misread aloud or on a
/// small screen). 32 symbols, so 32^6 (about 1 billion) codes.
const String roomCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int roomCodeLength = 6;

/// Upper-cases a typed or pasted code and drops spaces and dashes.
String normalizeRoomCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// True when [code] is well formed (right length, only allowed symbols).
bool isValidRoomCode(String code) {
  if (code.length != roomCodeLength) return false;
  for (final c in code.split('')) {
    if (!roomCodeAlphabet.contains(c)) return false;
  }
  return true;
}

/// Message types (`t`).
abstract final class Msg {
  // client -> server
  static const hello = 'hello';
  static const createRoom = 'create_room';
  static const joinRoom = 'join_room';
  static const ready = 'ready';
  static const start = 'start';
  static const place = 'place';
  static const move = 'move';
  static const capture = 'capture';
  static const pressPhutas = 'press_phutas';
  static const emote = 'emote';
  static const offerRematch = 'offer_rematch';
  static const acceptRematch = 'accept_rematch';
  static const leave = 'leave';
  static const report = 'report';
  static const ping = 'ping';

  // server -> client
  static const welcome = 'welcome';
  static const error = 'error';
  static const roomState = 'room_state';
  static const gameState = 'game_state';
  static const event = 'event';
  static const pong = 'pong';
  static const ack = 'ack';

  /// Client messages that carry a `seq` (idempotent, ordered).
  static const sequenced = {
    ready,
    start,
    place,
    move,
    capture,
    pressPhutas,
    emote,
    offerRematch,
    acceptRematch,
    leave,
    report,
  };
}

/// Event kinds (`event.kind`).
abstract final class EventKind {
  static const placed = 'placed';
  static const moved = 'moved';
  static const captureRequired = 'capture_required';
  static const machyas = 'machyas';
  static const eaten = 'eaten';
  static const begi = 'begi';
  static const treghi = 'treghi';
  static const phutasAvailable = 'phutas_available';
  static const phutasPressed = 'phutas_pressed';
  static const timeout = 'timeout';
  static const disconnected = 'disconnected';
  static const reconnected = 'reconnected';
  static const emote = 'emote';
  static const gameOver = 'game_over';
}

/// Why a game ended, as sent on the wire. The first four are the engine's own
/// reasons; the last two exist only online.
abstract final class EndReason {
  static const tokensReduced = 'tokensReduced';
  static const noLegalMoves = 'noLegalMoves';
  static const repetition = 'repetition';
  static const disqualified = 'disqualified';

  /// A player dropped and did not return within the reconnect window.
  static const abandoned = 'abandoned';

  /// A player pressed "Leave game".
  static const forfeit = 'forfeit';
}

/// Error codes (`error.code`).
abstract final class ErrorCodes {
  static const badRequest = 'bad_request';
  static const unsupportedVersion = 'unsupported_version';
  static const unauthorized = 'unauthorized';
  static const roomNotFound = 'room_not_found';
  static const roomExpired = 'room_expired';
  static const roomFull = 'room_full';
  static const roomClosed = 'room_closed';
  static const alreadyInRoom = 'already_in_room';
  static const notInRoom = 'not_in_room';
  static const notHost = 'not_host';
  static const notReady = 'not_ready';
  static const notYourTurn = 'not_your_turn';
  static const wrongPhase = 'wrong_phase';
  static const illegalMove = 'illegal_move';
  static const noCapturePending = 'no_capture_pending';
  static const illegalCapture = 'illegal_capture';
  static const capturePending = 'capture_pending';
  static const gameNotActive = 'game_not_active';
  static const seqGap = 'seq_gap';
  static const rateLimited = 'rate_limited';
  static const nameInvalid = 'name_invalid';
  static const emoteUnknown = 'emote_unknown';
  static const rematchUnavailable = 'rematch_unavailable';
  static const serverBusy = 'server_busy';
  static const internal = 'internal';
}

/// WebSocket close codes.
abstract final class CloseCodes {
  /// The server is restarting (a deploy). WebSocket libraries only let
  /// applications send 1000 or 3000-4999, so this is not 1001. Clients
  /// reconnect with the normal backoff.
  static const goingAway = 4004;
  static const outdated = 4000;
  static const unauthorized = 4001;
  static const replaced = 4002;
  static const rateLimited = 4003;
}

/// The only emotes that exist (no free-text chat).
const List<String> emoteIds = [
  'machyas',
  'nice_one',
  'oops',
  'good_game',
  'thinking',
  'thanks',
];
