# Naw Tin online server

WebSocket server for private-room play between remote friends. It is the single
source of truth: it owns the game state, validates every move with the shared
engine (`packages/naw_tin_core`), owns the turn clock and broadcasts confirmed
state. The wire format is in [`docs/online_protocol.md`](../docs/online_protocol.md).

## Run it locally (no Firebase needed)

```powershell
cd server
dart pub get
$env:NAWTIN_TEST_AUTH = "1"      # accept fake "test:<uid>" tokens - LOCAL ONLY
dart run bin/server.dart
```

```bash
cd server && dart pub get && NAWTIN_TEST_AUTH=1 dart run bin/server.dart
```

It listens on `:8080` (`PORT` to change). Check it: `http://localhost:8080/healthz`
answers `ok`. Clients connect to `ws://localhost:8080/ws` and send
`{"t":"hello","protocol":1,"token":"test:alice","name":"Alice"}` first.

Test mode is **off by default**. When it is on the server prints a loud warning,
and it **refuses to start** if it detects Cloud Run (`K_SERVICE` / `K_REVISION`),
so a deployed server can never accept fake tokens.

## Environment variables

| variable | meaning | default |
|---|---|---|
| `PORT` | listen port (Cloud Run sets it) | `8080` |
| `FIREBASE_PROJECT_ID` | Firebase project whose ID tokens are accepted (required unless test auth); this app: `nawtin-41c14` | - |
| `NAWTIN_TEST_AUTH` | `1` accepts `test:<uid>` tokens (local development only) | off |
| `NAWTIN_TURN_SECONDS` | per-turn clock | `120` |
| `NAWTIN_RECONNECT_SECONDS` | reconnect window | `45` |
| `NAWTIN_ROOM_MINUTES` | waiting-room lifetime | `10` |

Rooms live in memory: run **one instance** (Cloud Run `max-instances=1`,
`--session-affinity` not needed) for phase 1. See the deployment guide (Stage 6).

## Tests

```
cd server
dart pub get
dart test
```

88 tests cover: room lifecycle and codes, expiry, illegal-move rejection, the
two-step capture (protected tokens), the server clock, first and second timeouts
(including a pending capture), reconnects and the 45 s window, instant forfeit on
Leave, duplicate / out-of-order messages, rematch seat swaps, auth (including real
RS256 JWTs signed with a local test key), test-mode guardrails, rate limits, name
filtering, whole simulated games checked against a local engine replay (with
disconnects), and a real-socket smoke test.

## Layout

```
bin/server.dart        entry point (env -> config -> verifier -> serve)
lib/src/room.dart      one room: lobby, game, clock, timeouts, reconnects, rematch
lib/src/server.dart    connections, hello/auth, rate limits, room manager, HTTP + WebSocket
lib/src/auth.dart      Firebase ID-token verifier + test-mode verifier
lib/src/config.dart    environment config and the safety guardrails
lib/src/clock.dart     SystemClock / FakeClock (everything time-based is testable)
Dockerfile             build from the repository root (see its header)
```
