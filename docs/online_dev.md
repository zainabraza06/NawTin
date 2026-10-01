# Trying online play on your machine

Online play needs the server ([server/](../server/README.md)) and two players. In a
**debug** build the app signs in with a fake token, so no Firebase setup is needed;
release builds never do.

## 1. Start the server (test mode)

```powershell
cd server
dart pub get
$env:NAWTIN_TEST_AUTH = "1"     # fake "test:<uid>" tokens - LOCAL ONLY
dart run bin/server.dart        # listens on :8080
```

It prints a loud warning in this mode and refuses to start on Cloud Run.

## 2. Point the app at it

The address is `--dart-define=NAWTIN_SERVER=...`. If you leave it out, a **debug**
build picks a sensible default:

| Where the app runs | Default address |
|---|---|
| Android emulator | `ws://10.0.2.2:8080/ws` (the emulator's name for your PC) |
| Windows / web / iOS simulator | `ws://localhost:8080/ws` |
| A real Android phone | needs one of the two options below |

Real phone, USB cable: `adb reverse tcp:8080 tcp:8080`, then
`flutter run --dart-define=NAWTIN_SERVER=ws://localhost:8080/ws`.
Real phone, same Wi-Fi: use your PC's address
(`--dart-define=NAWTIN_SERVER=ws://192.168.1.20:8080/ws`) and allow port 8080 in the
Windows firewall.

Plain `ws://` is allowed by **debug builds only** (Android: the debug manifest
turns cleartext on; the main manifest forbids it). A release build accepts
`wss://` only and reports online play as unavailable otherwise.

## 3. Two players

Each install gets its own fake id (`dev-xxxxx`, saved on the device), so two
emulators, or an emulator plus Chrome, are two different players. To impersonate a
fixed id: `--dart-define=NAWTIN_DEV_UID=alice`.

Open **Settings -> Online test console (debug)** (debug builds only):

1. Both players: **Connect**.
2. Player 1: **Create room**. Player 2: type the code, **Join**, then **Ready**.
3. Player 1: **Start (host)**. The board appears; the coin flip decides who moves.
4. Play. Make a line to see the "tap a glowing token" capture step.

## 4. Things worth trying

- Switch a phone to **airplane mode** mid-game and back: the console shows
  reconnecting, then a full resync; the opponent sees "Opponent disconnected,
  reconnecting..." with a countdown.
- **Background** the app, or swipe it away, and reopen it inside 45 seconds: the
  match carries on ("Rejoin <code>" appears after a restart). It must never forfeit.
- **Leave game...** asks for confirmation and then forfeits at once.
- Let the clock run out: the first timeout plays a move for you, a second one in a
  row loses (same rule as offline).

## 5. Firebase (for the real sign-in, next stage)

| | |
|---|---|
| Project id | `nawtin-41c14` |
| Android package | `com.zainab.nawtin` |
| Android config | `android/app/google-services.json` - **git-ignored on purpose**; each machine / CI gets its own copy |
| iOS config | `ios/Runner/GoogleService-Info.plist` - also git-ignored |
| Server | `FIREBASE_PROJECT_ID=nawtin-41c14` (no test auth) |

The Firebase client config is not a secret, but keeping it out of the repository
avoids committing an API key by accident; restrict that key to this app in the
Google Cloud console. Anonymous Auth must be enabled in the Firebase console
(Authentication -> Sign-in method).
