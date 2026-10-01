# Naw Tin online protocol - version 1

Private-room play between two remote players. The **server is the single source
of truth**: it owns the game state, validates every move with the shared rules
engine (`packages/naw_tin_core`), owns the turn clock and broadcasts confirmed
state. Clients only send *intentions* ("I want to place on point 9").

* Transport: WebSocket, JSON text frames (UTF-8), one JSON object per frame.
* Endpoint: `wss://<host>/ws`
* Protocol version: `1`. The server also advertises `minProtocol`.
* Point numbering, line numbering, masks and seats are exactly those of the
  engine (`Board`): points `0..23` (`ring * 8 + pos`), seats `0` and `1`.

## 1. Envelope

Every frame:

```jsonc
{ "v": 1, "t": "<type>", ...payload }
```

Client to server frames may also carry:

| field | meaning |
|---|---|
| `seq` | integer, see section 3 (idempotency). Omit or `0` for connection-level messages. |
| `id`  | optional client request id, echoed in the `error` that rejects it. |

Server to client frames always carry:

| field | meaning |
|---|---|
| `ts` | server wall-clock, milliseconds since the Unix epoch (clock sync). |
| `ack` | highest client `seq` the server has processed for this room (when in a room). |
| `rev` | room revision, a counter that increases with every state change (room and game messages). Clients ignore anything with `rev` lower than what they hold. |

Unknown fields and unknown message types must be **ignored**, never treated as
errors. That is how the protocol grows without breaking old clients (see
section 12).

## 2. Connection and authentication

1. The client opens the WebSocket.
2. The client's first frame must be `hello` (within 5 seconds, otherwise the
   server closes with code `4001`).
3. The server verifies the Firebase **ID token** (anonymous auth is accepted),
   checks the protocol version and answers `welcome`.

```jsonc
// client -> server
{ "v":1, "t":"hello",
  "protocol": 1,
  "token": "<Firebase ID token>",
  "name": "Zainab",            // 2-16 chars, validated (section 9)
  "avatar": 3,                 // optional index into the built-in avatar set
  "appVersion": "0.1.0+1",     // informational, for logs
  "resume": "K7TQ3M" }         // optional: room code to rejoin after a drop

// server -> client
{ "v":1, "t":"welcome", "ts":1760000000000,
  "userId": "firebase-uid",
  "protocol": 1, "minProtocol": 1,
  "resume": { "code":"K7TQ3M", "status":"playing" } }   // only if that room is still open for this user
```

Token verification (server): RS256 JWT signed by Google's securetoken keys,
`aud` = the Firebase project id, `iss` = `https://securetoken.google.com/<project>`,
not expired. `firebase.sign_in_provider` may be `anonymous` or later `google.com`;
the `userId` is the token's `sub`, so linking Google sign-in later keeps the same
id. A header `Authorization: Bearer <token>` on the upgrade request is also
accepted where the platform allows it (not possible from browsers), but
`hello` is the portable path.

Only three things are stored about a user: `userId`, `name`, `avatar`.

**Local testing only:** a server started with `NAWTIN_TEST_AUTH=1` also accepts
fake tokens of the form `test:<uid>`. That mode is off by default, the server
prints a loud warning when it is on, and it **refuses to start** on Cloud Run
(`K_SERVICE` / `K_REVISION` present).

### Version refusal

If `hello.protocol < minProtocol` the server answers

```json
{ "v":1, "t":"error", "code":"unsupported_version", "fatal":true,
  "message":"Please update the app to play online." }
```

and closes with code `4000`. The client must show the designed "outdated app"
state, never a raw error.

### One connection per user

A new authenticated connection for a `userId` replaces the old one: the old socket
is closed with `4002` ("opened on another device"). The player's seat in a room
is kept.

### Close codes

| code | meaning |
|---|---|
| 1001 | server going away (deploy); reconnect with backoff |
| 4000 | outdated client |
| 4001 | unauthorized / handshake timeout / bad token |
| 4002 | replaced by a newer connection |
| 4003 | rate limited or blocked |

## 3. Ordering and idempotency

Mobile networks drop and retry, so every **room-level** client message carries a
`seq`.

* `seq` is a counter **per user per room**, starting at `1`, increasing by exactly
  `1` for each of: `ready`, `place`, `move`, `capture`, `press_phutas`, `emote`,
  `offer_rematch`, `accept_rematch`, `leave`, `report`.
* `hello`, `create_room`, `join_room` and `ping` are unsequenced (`seq` absent or
  `0`).
* The server remembers `lastSeq` for each player in the room:
  * `seq == lastSeq + 1`: process it, set `lastSeq`.
  * `seq <= lastSeq`: **duplicate**. Ignore it silently (do not apply twice) and
    re-send the current `ack`.
  * `seq > lastSeq + 1`: **gap**. Reject with `error` `seq_gap` and send a fresh
    `room_state` + `game_state` so the client can resync.
* After a reconnect, `room_state` tells the client its own `lastSeq`
  (`players[].lastSeq` for itself), so it continues from `lastSeq + 1` and can
  safely **resend** anything that was not acknowledged.
* The client keeps unacknowledged messages and resends them in order after a
  reconnect. Duplicates are harmless by construction.
* A message refused with `rate_limited` is **not processed and does not consume
  its `seq`**: after `retryAfterMs` the client resends it with the same number
  (sending later numbers first would be answered with `seq_gap`).

## 4. Client to server messages

| `t` | payload | notes |
|---|---|---|
| `hello` | see section 2 | first frame only |
| `create_room` | `{}` | makes a private room, the sender becomes host. Reserved: `mode` (default `"private"`). |
| `join_room` | `{ "code": "K7TQ3M" }` | case-insensitive; spaces/hyphens ignored |
| `ready` | `{ "ready": true }` | lobby readiness (host may start only when the guest is ready) |
| `start` | `{}` | host only, when both players are present and the guest is ready. *(Needed for "the host starts"; sequenced like the others.)* |
| `place` | `{ "to": 9 }` | placement step |
| `move` | `{ "from": 3, "to": 2 }` | slide step |
| `capture` | `{ "point": 20 }` | answers a `capture_required`, same turn |
| `press_phutas` | `{}` | the warning button; no effect on rules |
| `emote` | `{ "id": "nice_one" }` | preset ids only (section 9) |
| `offer_rematch` | `{}` | after `game_over` |
| `accept_rematch` | `{}` | answers the opponent's offer |
| `leave` | `{}` | the explicit Leave button only: leaves the lobby, or **instantly forfeits** a live game |
| `report` | `{ "userId": "...", "reason": "afk" }` | after a game (Stage 5) |
| `ping` | `{ "n": 123, "rtt": 42 }` | heartbeat every 15 s; unsequenced. `n` is echoed; `rtt` (optional) is the client's last measured round trip, shown to the opponent as a ping indicator |

### Placement and movement are two-step when a line is made

The server decides whether a step completes a line:

1. Client sends `place` / `move`.
2. If **no line** is completed, the server applies it at once.
3. If a line **is** completed (MACHYAS), the server does *not* apply it yet. It
   stores the step as `pending` and sends `event` `capture_required` with the legal
   targets (protected tokens excluded unless every opponent token is protected,
   exactly the engine's `captureTargets`). The **clock keeps running**.
4. The client sends `capture { point }`. The server checks `point` against the
   pending targets and applies step + capture atomically.

`pending` is part of every `game_state`, so a reconnecting client lands directly
back in the "choose a token to eat" state.

## 5. Server to client messages

### `welcome` - see section 2

### `error`

```json
{ "v":1, "t":"error", "code":"illegal_move",
  "message":"That move is not allowed.", "ref": 14, "id":"c-91", "fatal": false }
```

`ref` is the rejected message's `seq`, `id` its request id. `message` is short,
human-readable English meant to be shown as-is (clients may localise by `code`).
`fatal: true` means the server is about to close the socket.

| code | when |
|---|---|
| `bad_request` | malformed frame, wrong types |
| `unsupported_version` | client too old (fatal) |
| `unauthorized` | missing/invalid/expired token (fatal) |
| `room_not_found` | no such code |
| `room_expired` | the 10-minute waiting window ended |
| `room_full` | two players already |
| `room_closed` | the room was closed |
| `already_in_room` | the user is in another live room (rejoin it first) |
| `not_in_room` | room-level message without a room |
| `not_host` | `start` from the guest |
| `not_ready` | `start` before everyone is ready |
| `not_your_turn` | acting out of turn |
| `wrong_phase` | e.g. `move` while tokens are still to be placed |
| `illegal_move` | the engine rejects the step |
| `no_capture_pending` / `illegal_capture` | `capture` without a pending step / bad target |
| `capture_pending` | a new step while a capture is awaited |
| `game_not_active` | the game is over or not started |
| `seq_gap` | missed messages; a resync follows |
| `rate_limited` | includes `retryAfterMs` |
| `name_invalid` | rejected display name |
| `emote_unknown` | not a preset id |
| `rematch_unavailable` | no offer to accept |
| `server_busy` | temporary overload; retry |
| `internal` | bug; logged, the room survives |

### `room_state`

Sent on join, on every lobby change, and as part of every resync.

```jsonc
{ "v":1, "t":"room_state", "ts":..., "rev":4, "ack":2,
  "code": "K7TQ3M",
  "status": "lobby",               // waiting | lobby | playing | finished | closed
  "expiresAt": 1760000600000,      // only while waiting/lobby: when the room dies
  "host": "uidA",
  "mode": "private",               // reserved for "ranked"/"quick" later
  "players": [
    { "userId":"uidA", "name":"Zainab", "avatar":3, "connected":true, "ready":true,
      "seat": null, "pingMs": 42, "lastSeq": 2, "rating": null },
    { "userId":"uidB", "name":"Sam", "avatar":1, "connected":true, "ready":false,
      "seat": null, "pingMs": 80, "lastSeq": 0, "rating": null }
  ],
  "rules": { "placementRule":"symmetricOpening", "turnSeconds":120,
             "reconnectSeconds":45, "seatAssignment":"coin_flip" },
  "coinFlip": null,                // after start: { "seat0": "uidB" }
  "rematch": { "offeredBy": null } // or a userId
}
```

`seat` is `0`/`1` once the game has started (seat `0` moves first). `rating`
is always `null` in phase 1 and exists so matchmaking can add it without a
protocol change.

### `game_state` (full snapshot)

```jsonc
{ "v":1, "t":"game_state", "ts":..., "rev":9, "ack":5,
  "snapshot": {
    "mask0": 4195, "mask1": 66048,       // 24-bit masks of tokens on the board
    "hand0": 6, "hand1": 7,              // tokens still to place
    "turn": 1, "placesLeft": 1,
    "phase": "placement",                // placement | movement
    "result": null                       // or { "winner": 0|1|null, "reason": "tokensReduced" }
  },
  "pending": null,                       // or { "from": -1, "to": 2, "targets": [20, 22] }
  "clock": { "seat": 1, "deadline": 1760000090000, "totalMs": 120000, "graceMs": 1500 },
  "timeouts": [0, 0],                    // timeouts in a row per seat
  "stats": { "eaten":[0,1], "lines":[0,1], "swings":[0,0] },
  "phutas": { "seat": 0, "lines": 1 },   // available to press, or null
  "lastMove": { "seat": 0, "from": 3, "to": 2, "capture": 20 },
  "lastEvent": "eaten" }
```

* `snapshot` is the engine `GameState` minus the repetition history. The server
  keeps the history (3-fold repetition is decided server-side).
* `clock.deadline` is the server epoch time by which `clock.seat` must have
  acted. It already includes `graceMs`, extra time added after a move so
  animations never cost the next player time.
* `lastMove` + `lastEvent` give clients what they need to play the animation
  after a reconnect.

Every confirmed change produces **`event` messages followed by one
`game_state`** with the same `rev`. A client animates from the events, then
reconciles to the snapshot (the snapshot always wins).

### `event`

```jsonc
{ "v":1, "t":"event", "ts":..., "rev":9, "kind":"moved",
  "seat":0, "data": { "from":3, "to":2 } }
```

| `kind` | `data` |
|---|---|
| `placed` | `{ to }` |
| `moved` | `{ from, to }` |
| `capture_required` | `{ from, to, targets:[...] }` (to the acting player; the opponent sees a "choosing" indicator) |
| `machyas` | `{ lines: <16-bit line mask> }` |
| `eaten` | `{ point, seat }` (the seat that lost the token) |
| `begi` / `treghi` | `{ stops:[...], ready:bool }` (`ready` true when formed during placement) |
| `phutas_available` | `{ lines }` - the mover set up a new threat |
| `phutas_pressed` | `{}` |
| `timeout` | `{ seat, count, auto: true|false, disqualified: bool }` |
| `disconnected` | `{ seat, reconnectDeadline, reason: "dropped" }` |
| `reconnected` | `{ seat }` |
| `emote` | `{ seat, id }` |
| `game_over` | `{ winner: 0|1|null, reason }` where reason is `tokensReduced`, `noLegalMoves`, `repetition`, `disqualified`, `abandoned` or `forfeit` |

The facts around one move always arrive in this order:
`placed|moved` -> `machyas` -> `eaten` -> `begi|treghi` -> `phutas_available` ->
`game_over`.

### `ack`

```json
{ "v":1, "t":"ack", "ts":..., "ack": 12 }
```

Sent when the server receives a sequenced message it has already processed (a
duplicate). It changes nothing; it just tells the client the highest `seq` the
server holds, so the client can drop its resend queue.

### `pong`

```json
{ "v":1, "t":"pong", "ts":1760000000123, "n":123 }
```

`n` echoes the client's `ping.n`.

## 6. Room lifecycle

```
create_room            -> status "waiting"  (expires 10 min after creation)
guest join_room        -> status "lobby"    (expiry window refreshed to 10 min)
guest ready + start    -> coin flip -> seats -> status "playing"
game_over              -> status "finished" (stays open for a rematch, 5 min)
accept_rematch         -> seats swap -> status "playing" again
everyone gone / expired -> status "closed"
```

* **Codes:** 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no `0 O 1 I`),
  generated with a cryptographically secure RNG, unique among live rooms.
  Share link: `https://<your-domain>/join/K7TQ3M`; custom scheme
  `nawtin://join/K7TQ3M`.
* **Leaving the lobby:** if the host leaves, the room closes (the guest receives
  `room_state` status `closed`). If the guest leaves, the room goes back to
  `waiting` with its remaining time.
* **Leaving during a game:** only the in-app **Leave game** button (behind a
  confirmation: "Leave the game? You'll forfeit.") sends `leave`, and it is an
  **instant forfeit**: `game_over` with reason `forfeit`, no waiting. Clients
  must never send `leave` for anything else: backgrounding the app, closing it,
  losing the connection or being killed all keep the 45-second window below.
* **Seat assignment:** at `start` the server flips a coin (secure RNG) and sends
  `coinFlip`. With `seatAssignment: "engine"` it would follow the engine's
  configured balance instead. On a **rematch the seats swap**, so the player who
  moved second now starts (the first mover has a small edge).
* **Rules in force** travel in `room_state.rules` so a future client can refuse a
  server whose rules it does not implement. Phase 1 server: `placementRule`
  `symmetricOpening`, `turnSeconds` `120`.

## 7. Timers

The server owns the turn clock (two-player value, 120 s). Both clients render
`clock.deadline - serverNow`, where

```
offset = serverTs - clientNowAtReceive + rtt/2        (smoothed over several pongs)
serverNow = clientNow + offset
```

* The clock for an action starts when the previous action is confirmed (plus
  `graceMs`). Each placement or slide gets its own full clock, like offline.
* **First timeout:** the server plays a basic legal move for that seat (the
  Easy-strength search from the shared package - never the Hard hint search -
  including the token to eat if a capture was pending). `event timeout
  { count: 1, auto: true }`.
* **Second timeout in a row:** the player is disqualified: `timeout
  { count: 2, disqualified: true }` then `game_over` reason `disqualified`. A move
  the player makes themselves resets their count.
* **No pausing online.** The clock keeps running while a player is disconnected;
  a timeout that fires for a disconnected player auto-plays as usual.

## 8. Disconnects and reconnects

* The server detects a drop by socket close or by 45 s without any frame
  (heartbeats every 15 s keep a live socket busy).
* `event disconnected { seat, reconnectDeadline }` goes to the opponent, who shows
  "Opponent disconnected, reconnecting..." with a countdown.
* **Reconnect window: 45 s.** On `hello` (with `resume` = room code) the server
  re-attaches the user to the room, sends `welcome`, then a full `room_state` +
  `game_state`, and emits `event reconnected`.
* If the window passes: the absent player forfeits - `game_over` reason
  `abandoned`.
* The client stores `{ roomCode }` locally while in a room and offers **Rejoin
  game** from the home screen after an app kill. If the room is gone the server
  answers `room_not_found` / `room_expired` and the client clears the stored code.
* Client reconnect backoff: 0.5 s, 1 s, 2 s, 4 s, 8 s, then every 8 s, with
  jitter, until the window is over.

## 9. Safety and abuse

* **No free text in play.** Chat does not exist. `emote` accepts only these ids:
  `machyas`, `nice_one`, `oops`, `good_game`, `thinking`, `thanks`.
  Rate limit: 1 per 3 s, at most 6 per minute, per user.
* **Display names:** 2-16 characters, letters/digits/space/`_`/`-` only, trimmed,
  no leading/trailing or doubled spaces, profanity filtered (the server holds the
  list and normalises look-alikes such as `0`->`o`). Rejection: `name_invalid`.
  Clients should offer a generated name (adjective + animal) by default.
* **Rate limits** (defaults, per user and per IP, token buckets):

  | what | limit |
  |---|---|
  | `create_room` | 5 per 10 min |
  | `join_room` attempts | 10 per 10 min per user, 30 per 10 min per IP (code guessing); five failures in a row add a one-minute lockout |
  | room-level messages | 20 per 10 s |
  | new connections | 20 per minute per IP |

  Breaches answer `rate_limited` with `retryAfterMs`; sustained abuse closes the
  socket with `4003`.
* **The server never trusts client state.** Clients send only intentions; the
  server rebuilds every position from its own engine state.
* **Reports:** `report { userId, reason }` (`afk`, `abusive_name`, `cheating`,
  `other`) records `{ roomId, reportedUserId, reporterUserId, reason, time }`.
  No automated action in phase 1.
* **Logging:** structured logs with the anonymous `userId`, room id, message
  type, error code and timing only: no IP addresses in application logs (the
  platform's request log handles those), no names, no IDs beyond the Firebase
  uid.

## 10. Reserved for later (do not use yet)

Message types `queue_join`, `queue_leave`, `match_found`; room `mode` values
`"quick"` and `"ranked"`; `players[].rating`; sign-in linking (the token's `sub`
stays stable when an anonymous user links Google). Receivers ignore them today.

## 11. Example: a short game

```
C1 -> hello{token,name}                 S  -> welcome{userId}
C1 -> create_room                       S  -> room_state{code:"K7TQ3M", status:"waiting"}
C2 -> hello ; join_room{code}           S  -> room_state{status:"lobby"} (to both)
C2 -> ready{true} seq1                  S  -> room_state (ack:1)
C1 -> start seq1                        S  -> room_state{status:"playing", coinFlip} + game_state rev 1
C1 -> place{to:0} seq2                  S  -> event placed ; game_state rev 2 ; (placesLeft 1)
C1 -> place{to:1} seq3                  S  -> event placed ; phutas_available ; game_state rev 3
C1 -> press_phutas seq4                 S  -> event phutas_pressed
...
C2 -> place{to:10} seq9                 S  -> event capture_required{targets:[0,1,3]} (to C2)
C2 -> capture{point:3} seq10            S  -> placed, machyas, eaten, game_state
C2 -> place{to:10} seq9  (resent)       S  -> (ignored: duplicate, ack stays 10)
```

## 12. Versioning rules

* Adding a field, an event kind, an error code or a message type is **not** a
  breaking change: receivers must ignore what they do not know.
* Changing the meaning of an existing field, removing one, or changing a rule the
  client depends on **bumps `v`**. The server then raises `minProtocol` only when
  it can no longer serve old clients; until then it keeps answering them in their
  own version.
* `appVersion` is for diagnostics only. Compatibility is decided by `protocol`.
