# Naw Tin - store and privacy checklist (online play)

What to declare, configure and check before publishing the version that has
online play. It extends [PLAY_STORE.md](PLAY_STORE.md) (build, signing, listing)
and uses the wording of [PRIVACY_POLICY.md](PRIVACY_POLICY.md). Items marked
**YOU** need your accounts or a decision; nothing here can be done from code.

> This is a working list written from what the app and server actually do. It is
> not legal advice, and the Play Console forms change: re-read each question
> against the live form and Google's current Data safety help before you submit.

## 1. What the app really sends (the facts the forms must match)

| Data | Where it comes from | Where it goes | How long it lives |
|---|---|---|---|
| Anonymous user id (Firebase uid) | created on first online use, no login | Firebase Auth; sent to our server inside the ID token | until the app data is cleared / uninstalled (Firebase may keep the anonymous account until you delete it; auto clean-up is **off**) |
| Display name (2-16 chars, filtered) | the player types it, or a generated one | our server, shown to the other player | in server memory while the player is in a room; also saved on the phone |
| Room code, moves, ready/start/rematch, preset emote ids | the game | our server, the other player | in server memory until the room ends or expires (waiting room: 10 min). No game history is stored |
| Reports (reporter id, reported id, room, reason from a list, time) | the "Report" button | our server log | log retention period **YOU choose** (see 6) |
| Server logs (anonymous id, room, message type, error code, timing) | server | Cloud Logging | log retention period **YOU choose** |
| IP address | every network request | Google Cloud's own request logs | Google's retention; the app's own logs do not store IPs |
| Advertising id etc. | AdMob SDK (offline hints and rewind only) | Google AdMob | per Google |

Not collected: name from an account, email, phone, contacts, photos, files,
location (beyond what an IP address implies), microphone, camera, health,
payment data. No analytics SDK, no crash-reporting SDK, no free-text chat.
**There are no ads during an online game** (enforced by a test that fails if
anything under `lib/features/online` imports the ads code).

## 2. Play Console: Data safety form

Answer *Yes* to "Does your app collect or share any of the required user data
types".

| Data type (Play category) | Collected | Shared | Ephemeral? | Required or optional | Purpose |
|---|---|---|---|---|---|
| **Personal info > User IDs** (Firebase anonymous uid) | Yes | No (Firebase and Cloud Run process it on our behalf as service providers) | No | Required for online play | App functionality; Fraud prevention, security, and compliance |
| **Personal info > Name** (the display name; it can be a made-up nickname) | Yes | No | Yes (held in server memory only) | Optional (a generated name is used if the player does not choose one) | App functionality |
| **App activity > Other actions** or *App interactions* (moves and preset emotes) | Yes | No | Yes (deleted when the room ends) | Required for online play | App functionality |
| **Device or other IDs** (advertising id) | Yes (AdMob) | Yes, with Google AdMob | No | Required for the rewarded ads | Advertising or marketing |
| Whatever else the AdMob SDK collects (for example approximate location from IP, diagnostics, app interactions) | Yes (AdMob) | Yes, with Google AdMob | per Google | - | Advertising or marketing, Analytics |

* For the AdMob rows, copy Google's current **"Data disclosure for AdMob"**
  guidance exactly; it is longer than the list above and it changes.
* "Is all of the user data collected by your app encrypted in transit?" **Yes**
  (online traffic is `wss://` only in release builds; this is tested).
* "Do you provide a way for users to request that their data be deleted?"
  **Yes**: uninstall or clear the app's data removes the anonymous identity from
  the phone, and the contact address in the privacy policy handles requests about
  server logs. **YOU** must keep that mailbox working.
* **Account deletion question:** the app has no user-created accounts (no sign-up
  screen); the anonymous Firebase identity is created silently. Answer
  "My app doesn't allow users to create an account". **Re-check this answer
  with Google's current definition before submitting**, because the Play
  review team treats an automatically created anonymous account differently
  from some other cases. If they ask, the answer is the deletion route above.
* The declarations must match the privacy policy word for word where they overlap.

## 3. Privacy policy

* [PRIVACY_POLICY.md](PRIVACY_POLICY.md) already has the online section.
  **YOU**: fill every `[PLACEHOLDER]` (name, country, email, date, log retention
  period), have it reviewed, host it on a public page, and put the URL in
  Play Console > App content > Privacy policy **and** in the store listing.
* If you publish in the EEA, UK or Switzerland: add a consent flow (Google's
  User Messaging Platform) for the ads and describe it in the policy.
* Link to the policy from inside the app (Settings) so players can read it.
  *(Not done yet: add the URL once it exists.)*

## 4. Content rating (IARC questionnaire)

* Abstract strategy game, no violence, no gambling, no purchases.
* **Users can interact: yes**, through a fixed list of preset phrases (no
  free text, no images, no voice). **Shares user-generated content: no**
  (only a display name). **Shares location: no.**
* Expected: an "Everyone"-level rating, shown with a "users interact" notice.
  Answer the ads question truthfully.
* Target audience: **13+ / general audience; not designed for children** (that
  would bring the Families Policy and restrict ad networks and online features).

## 5. Google's User Generated Content policy (display names and reports)

Display names are user-generated. What the app does about it:

| Requirement | Status |
|---|---|
| Filter objectionable content | Names: 2-16 chars, letters/digits/space/`_`/`-`, profanity list with look-alike handling (server and app use the same rules) |
| In-app way to report | **Done**: Report button after every game, fixed reasons (not playing, offensive name, cheating, something else) |
| Act on reports | **YOU**: reports go to the server log as `report.received`; review them (6) and decide what to do. There is no automated action |
| Block users | Not built. Rooms are private, by code, one friend at a time, and a player can leave at any time. Add a block list if complaints appear |
| No free-text chat | By design; only six preset phrases, and "Hide emotes" turns them off |

## 6. Moderation and logs (operations)

* **Find reports:** in Cloud Logging filter on the text `report.received`
  (each entry has the room, reporter id, reported id, reason, time).
* **Decide the retention period** for logs (Cloud Logging buckets default to 30
  days) and write it into the privacy policy.
* Decide what you will do with repeat offenders. Today the only tool is not
  helping them: ids are anonymous and reset on reinstall, so be honest about
  that limit. (A ban list by uid is possible later; App Check below makes
  evading it harder.)

## 7. Firebase console (project `nawtin-41c14`)

- [ ] Authentication > Sign-in method: **Anonymous = Enabled**. Auto clean-up
      of anonymous accounts: **off**.
- [ ] Project settings > your Android app (`com.zainab.nawtin`): add the
      **SHA-1 and SHA-256 of the release key and of the Play App Signing key**
      (Play Console > Setup > App signing), as well as the debug key if you test
      with it.
- [ ] Google Cloud console > APIs & Services > Credentials: **restrict the
      Android API key** to the package name `com.zainab.nawtin` and the SHA-1
      fingerprints above, and to the APIs the app needs (Identity Toolkit /
      Firebase Auth).
- [ ] Recommended: turn on **Firebase App Check with Play Integrity** so only
      the genuine app can get tokens. (The server does not require it yet.)
- [ ] Set a **budget alert** on the Google Cloud billing account.
- [ ] Keep a backup of `android/app/google-services.json` (it is git-ignored;
      each machine and CI needs its own copy).

## 8. Server (Cloud Run; full guide in Stage 6)

- [ ] `FIREBASE_PROJECT_ID=nawtin-41c14`; **never** set `NAWTIN_TEST_AUTH`
      (the server refuses to start with it on Cloud Run).
- [ ] Rooms live in the memory of one instance: deploy with **max instances 1**
      (or add shared state first), and a request timeout long enough for a game.
- [ ] Only `wss://` is reachable (Cloud Run gives HTTPS/WSS by default).
- [ ] Health check `/healthz`; alert on restarts and on errors.

## 9. Build and release

- [ ] Release build flags: `--dart-define=NAWTIN_SERVER=wss://<your-service>/ws`
      and `--dart-define=ADS=admob`, signed with the upload key.
- [ ] Confirm the release app has no debug console, no fake sign-in, and refuses
      `ws://` (covered by `test/online/online_safety_test.dart`; also spot-check
      the built APK/AAB).
- [ ] AdMob: real app id and ad unit instead of the test ids; your own device as
      a test device; never click your own live ads.
- [ ] `flutter analyze`, `flutter test`, `dart test` in `packages/naw_tin_core`
      and `server` are all green.
- [ ] Version name/code bumped; "What's new" mentions online play.

## 10. Store listing

- [ ] Description: say it is a two-player online game with a private room code,
      no account, no chat, ads only for optional hints in offline play.
- [ ] New screenshots: Play Online menu, lobby with the code, an online game, game
      over with rematch (portrait phone sizes as in PLAY_STORE.md).
- [ ] Contact email and privacy policy URL on the listing.
- [ ] **Package name** `com.zainab.nawtin` is final the moment you upload.

## 11. Before you hit publish: a human test

Two real phones, release builds (or a closed-testing track): create/join with
the share message, play to the end, rematch, report, emotes and "Hide emotes",
airplane mode mid-game and back, kill the app and rejoin, outdated-app screen
(by raising the server's minimum protocol on a staging copy). The two-device
test plan with the exact steps comes with the deployment guide in Stage 6.
