# Two-device test plan for online play

A step-by-step script for testing Naw Tin online with **two real phones**. Do it
twice: once against your PC (debug build, free, fast to fix things), and once
against the deployed Cloud Run server with release builds (what players get).

Call the phones **A** and **B**. Tick each box as you go and write what you saw
in the notes column. Anything that is not exactly as expected is a bug worth
telling me about, with the step number.

## 0. Setup

### Round 1: against your PC (debug builds)

1. Server on the PC, real sign-in mode, port 8090:
   ```powershell
   $env:FIREBASE_PROJECT_ID="nawtin-41c14"; $env:PORT="8090"
   cd server; dart run bin/server.dart
   ```
   The first two log lines should be `auth.certs_ok: ...` and `Naw Tin server listening on :8090`.
2. Check it: `dart run tool/check.dart http://localhost:8090` (all PASS).
3. Windows Firewall: allow inbound TCP **8090** on **private networks only**; delete the rule when you finish.
4. Both phones on the **same Wi-Fi** as the PC. Build with your PC's Wi-Fi address (`ipconfig`):
   ```powershell
   flutter build apk --debug --target-platform android-arm64 `
     --dart-define=NAWTIN_REAL_AUTH=1 --dart-define=NAWTIN_SERVER=ws://<PC-IP>:8090/ws
   ```
   Install the same APK on A and B.
5. In the Firebase console: Authentication > Sign-in method > **Anonymous = Enabled**.

### Round 2: against Cloud Run (release builds)

1. Deploy ([deploy_cloud_run.md](deploy_cloud_run.md)); `check.dart` all PASS; logs show `auth.certs_ok`.
2. Build a release APK for the phones (or use a closed-testing track):
   ```powershell
   flutter build apk --release --dart-define=NAWTIN_SERVER=wss://<service-host>/ws --dart-define=ADS=admob
   ```
3. Put phones on **different networks** (A on Wi-Fi, B on mobile data): this is the real thing.

Useful throughout: watch the server logs on a laptop while you play.

## 1. Sign-in and menu

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 1.1 | A: fresh install, open the app, tap **Play Online** | Online screen; the dot goes amber then **green "Online"** within a few seconds. A name like "Brave Otter" is shown under "Playing as" | ☐ | |
| 1.2 | A: **Change** the name to something real; try `x` and a rude word | A valid name is saved; `x` and the rude word are each refused with "Please pick another name." | ☐ | |
| 1.3 | Server log | No errors; a connection for A's anonymous id | ☐ | |
| 1.4 | B: same as 1.1 | Online, a different generated name | ☐ | |

If 1.1 stays on a problem screen, note exactly which one:
"Couldn't sign you in" = Firebase (Anonymous not enabled, wrong `google-services.json`, or server project id);
"Can't reach the game server" = address / firewall / server down;
"No internet connection" = the phone really has no network.

## 2. Create, share, join, lobby

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 2.1 | A: **Create a room** | Lobby with a 6-character code, "Waiting for your friend...", Share and Copy buttons, a "Room closes in 9:5x" countdown | ☐ | |
| 2.2 | A: **Share** | The share sheet opens with the text "Play Naw Tin with me! ... enter: CODE". Send it to B (any messenger) | ☐ | |
| 2.3 | B: copy that message, open the app > Play Online > **Join with a code** | A chip **"Paste CODE"** appears; tapping it fills the six boxes | ☐ | |
| 2.4 | B: type a **wrong** code, e.g. `ZZZZZZ`, tap Join | "We couldn't find a game with that code." The boxes turn red; editing clears it | ☐ | |
| 2.5 | B: enter the real code, Join | Lobby for B showing A as the host; A's lobby now shows B | ☐ | |
| 2.6 | A: look at **Start game** before B is ready | Disabled, says "Waiting for your friend to get ready" | ☐ | |
| 2.7 | B: tap **I'm ready** (then try "Not ready" and back) | A's screen updates live; **Start game** enables when B is ready | ☐ | |
| 2.8 | A: **Start game** | Both phones go to the board. One has **YOUR TURN**, the other **THEIR TURN** (the coin flip) | ☐ | |

## 3. A full game

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 3.1 | Look at both screens | Same board, same token counts. Each player has **two** tokens to place on their first turn; both countdown rings agree **within 1 second** | ☐ | |
| 3.2 | Play several moves, alternating | Each move appears on both phones within about a second, with the placement/slide animation and sound | ☐ | |
| 3.3 | Tap when it is **not** your turn | Nothing is sent; caption says "Waiting for ..." | ☐ | |
| 3.4 | Make a line of three (Machyas) | The mover is asked to **tap a glowing opponent token**; the other phone shows the banner/shake; the eaten token disappears on both | ☐ | |
| 3.5 | Try to eat a **protected** token (in a line) while unprotected ones exist | Only unprotected ones glow | ☐ | |
| 3.6 | Set up a **Begi / Treghi** swing | Banner and flash on both phones | ☐ | |
| 3.7 | Use **PHUTAS** when it lights up | Both phones show the PHUTAS banner and sound | ☐ | |
| 3.8 | Confirm **no Hint and no Rewind** buttons, and **no ads** at any point | Only PHUTAS in the dock; no ad ever appears in an online game | ☐ | |
| 3.9 | Play to the end (down to two tokens, or no moves) | Both see the game-over panel: correct winner, reason, stats | ☐ | |

## 4. The clock and timeouts

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 4.1 | On B, set the phone's clock **5 minutes wrong** (turn off automatic time), then look at the countdown | Still agrees with A within 1 second (the app uses the server's clock). **Set the time back to automatic afterwards** | ☐ | |
| 4.2 | Let a player's 2-minute clock run out once | A simple move is played for them; a message says so and warns one more timeout in a row loses | ☐ | |
| 4.3 | Let the same player time out **twice in a row** | They lose ("Out of time twice in a row"); both see game over | ☐ | |
| 4.4 | After a timeout, make a normal move, then time out again | Counts as the *first* timeout again (the count resets when you move) | ☐ | |

(To save time, run the server with `NAWTIN_TURN_SECONDS=20`.)

## 5. Connection trouble (the important part)

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 5.1 | Mid-game, A: **airplane mode for ~10 s**, then off | A sees "Connection lost. Reconnecting..."; B sees "A lost connection. Waiting 45s..." with a countdown. When A returns both continue exactly where they were. **Nobody forfeits** | ☐ | |
| 5.2 | A: airplane mode for **more than 45 s** | B wins ("... left and did not come back"). A, on return, sees the game ended | ☐ | |
| 5.3 | A: press Home / switch app for ~20 s, come back | Game continues, no forfeit | ☐ | |
| 5.4 | A: **swipe the app away** (kill it), reopen within 45 s | Home screen shows **"Game in progress, Room XXXXXX" + Rejoin**. Tap it: back in the same game | ☐ | |
| 5.5 | Same as 5.4 but wait over 45 s | The game was lost by A. Tapping Rejoin shows either the game-over screen (A lost) or a clear "No game with that code" message. Either way the card is gone afterwards and nothing hangs | ☐ | |
| 5.6 | Home card: tap the **X** | Asks "Remove this game?"; confirming removes it | ☐ | |
| 5.7 | A: tap **Leave** (exit icon), then **Stay** | Nothing happens | ☐ | |
| 5.8 | A: tap **Leave**, then **Leave** | A loses at once; B sees "A left the game" | ☐ | |
| 5.9 | A: press the system **Back** button during a game | Same confirmation as Leave; it never forfeits silently | ☐ | |
| 5.10 | Switch A between Wi-Fi and mobile data mid-game | A short "reconnecting", then continues | ☐ | |
| 5.11 | Turn airplane mode on, then open Play Online | **"No internet connection"** screen with Try again; turning it off and tapping Try again connects | ☐ | |
| 5.12 | Stop the server (Round 1), then open Play Online | **"Can't reach the game server"** screen; restart the server and it connects by itself | ☐ | |
| 5.13 | Mid-game, restart/redeploy the server | Both show reconnecting, then "the room was closed" (rooms do not survive a restart) | ☐ | |

## 6. Rematch, emotes, reports

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 6.1 | After a game, A taps **Rematch** | A's button reads "Waiting for B..."; B's reads **"Accept rematch"** | ☐ | |
| 6.2 | B accepts | A new game starts at once; **first mover swaps** versus last game | ☐ | |
| 6.3 | If one player taps **Home** instead | The other sees "Your friend has left" and no rematch | ☐ | |
| 6.4 | In a game, open the emote button, send **Nice one** | A bubble appears on both phones for about 3 seconds | ☐ | |
| 6.5 | Send two emotes within 3 seconds | The second is held back with "Easy on the emotes" | ☐ | |
| 6.6 | There is no way to type text anywhere in the game | Only the six presets | ☐ | |
| 6.7 | B: emote picker > **Hide emotes** | B no longer sees A's emotes and has no emote button; A is unaffected | ☐ | |
| 6.8 | After a game, tap **Report ...** and choose a reason | "Thanks, your report was sent"; the button becomes "Reported". The server log has `report.received` | ☐ | |

## 7. Room edge cases

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 7.1 | A third phone (or B again) tries to join a full room | "That game already has two players." | ☐ | |
| 7.2 | Create a room and leave it unused 10 minutes (or run the server with `NAWTIN_ROOM_MINUTES=1`) | The room expires; joining it says it has expired | ☐ | |
| 7.3 | Host taps **Leave room** in the lobby | Confirmation, then back at the menu; the code no longer works | ☐ | |
| 7.4 | Create rooms rapidly (6+ in 10 minutes) | A friendly "You're going a little fast. Try again in N minutes." | ☐ | |
| 7.5 | Type a wrong code 6 times quickly | A friendly wait message, then it works again | ☐ | |

## 8. Release-only checks (Round 2)

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 8.1 | Settings in the release app | **No** "Online test console (debug)" entry | ☐ | |
| 8.2 | Run `check.dart` against the Cloud Run URL | All four PASS | ☐ | |
| 8.3 | Install a release build **without** `NAWTIN_SERVER` | Play Online shows "Online play is not available in this build" | ☐ | |
| 8.4 | Offline modes with airplane mode on | vs AI and two-players-on-one-phone still work; the hint ad says no ad is available | ☐ | |

## 9. Outdated app (optional)

Run the server with `minProtocolVersion` raised to 2 in
`packages/naw_tin_core/lib/src/protocol/protocol.dart`, and connect with the
current app. Expect the **"Please update the app"** screen with an **Update**
button (it opens the store page, which only exists after you publish). Put the
constant back afterwards.

## 10. Comfort and accessibility

| # | Do | Expect | OK | Notes |
|---|---|---|---|---|
| 10.1 | Turn on **TalkBack** on A; open the lobby and a game | The room code is read out; moves and turn changes are announced; every button has a name | ☐ | |
| 10.2 | Use a small/old phone, with Low-power mode on | Smooth enough; nothing cut off at 360 dp wide | ☐ | |
| 10.3 | Rotate the phone | The app stays portrait | ☐ | |
| 10.4 | Dark/light, large system font | Text readable, nothing overlaps | ☐ | |

## 11. Record

Fill in once per round.

| | |
|---|---|
| Date / round | |
| Server | PC (debug) / Cloud Run: URL, region |
| Phone A | model, Android version, network |
| Phone B | model, Android version, network |
| App build | version, debug/release |
| Failed steps | numbers + what you saw |
| Server log excerpts for failures | |

**Ready to publish when:** every step in sections 1 to 6 passes on Round 2 on two
different phones and networks, section 8 passes, and nothing in section 5 ever
forfeits a game by itself.
