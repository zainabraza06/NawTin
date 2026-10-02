# Naw Tin: from this repository to the Play Store

The whole path in order: accounts, Firebase, the server on Cloud Run, the
signed app, testing with two phones, and the Play Console. Each phase says what
you do, what to check, and links to the detailed page instead of repeating it.

| Detailed page | What it covers |
|---|---|
| [deploy_cloud_run.md](deploy_cloud_run.md) | the server on Google Cloud Run (settings, cost, rollback, troubleshooting) |
| [two_device_test_plan.md](two_device_test_plan.md) | the test script for two real phones |
| [store_checklist.md](store_checklist.md) | Data safety answers, content rating, Firebase console, user-content rules |
| [PLAY_STORE.md](PLAY_STORE.md) | signing, store listing copy, graphics |
| [PRIVACY_POLICY.md](PRIVACY_POLICY.md) | the privacy policy draft to complete and host |
| [online_protocol.md](online_protocol.md) | the wire protocol (for changing the server later) |

## Where things stand today

| Done and tested in code | Still to do (needs you, your accounts, or a phone) |
|---|---|
| Game, AI (3 levels), sound, accessibility, store graphics | Try **real Firebase sign-in** on a phone (never run on a device yet) |
| Online client, UI, emotes, reports, rejoin, all problem screens | **Deploy the server** (nothing is deployed yet) |
| Server: rooms, clocks, auth, rate limits, clean shutdown, startup self-check | Run the **two-phone test plan** |
| Docker image builds and runs; fetches Google's signing keys inside the image | Create the **upload key** and sign a release |
| Release build safety: no debug console, no fake sign-in, `wss://` only, no ads in online games | Replace the **AdMob test ids**; add an EEA consent flow if you publish there |
| Docs, privacy policy draft, store checklist | Fill the **privacy policy** placeholders and host it; Play Console forms and listing |

## The order matters

```
1 decisions and accounts
2 Firebase console
3 test everything on your PC first        (free, quick to fix)
4 deploy the server                       (before any app that needs it)
5 upload key and release build
6 test the release build on two phones against the real server
7 Play Console: internal -> closed testing -> production
8 after launch: watch, update, roll back
```

**Server first, app second.** Players can only use an app version whose protocol
the server still accepts. See "Updating later" at the end.

---

## Phase 1: decisions and accounts

Decide these before you spend anything.

- [ ] **Package name.** It is `com.zainab.nawtin` now. It becomes your Play Store
      id and **can never change** after the first upload. Keep it, or change it
      now in `android/app/build.gradle.kts` (`namespace`, `applicationId`), the
      Kotlin package folder, and re-register the Android app in Firebase.
- [ ] **Google Play Console** developer account (a one-time registration fee;
      check the current amount). Personal accounts created recently also have to
      run a closed test with a minimum number of testers for a minimum number of
      days before production: **check Google's current requirement** and start
      recruiting testers early.
- [ ] **AdMob** account, with one Android app and one *rewarded* ad unit.
- [ ] **Billing** on the Google project: in the Firebase console move
      `nawtin-41c14` from the free Spark plan to **Blaze** (pay as you go), then
      set a **budget alert** (Google Cloud console > Billing > Budgets & alerts).
      Do the alert first.
- [ ] **A public web page for the privacy policy** and a **support email** that
      you will actually read. A free static page (GitHub Pages, a Google Site)
      is enough.
- [ ] **A license** for the code if you will make the repository public (none
      added yet).
- [ ] **Region** for the server: nearest to your players
      (`asia-south1` Mumbai, `europe-west1`, `us-central1`, ...).

## Phase 2: Firebase console (project `nawtin-41c14`)

Open [console.firebase.google.com](https://console.firebase.google.com).

1. **Authentication > Sign-in method > Anonymous: Enabled.** Leave "Auto
   clean-up" off. (A disabled provider is the most common cause of "Couldn't sign
   you in".)
2. **Project settings > Your apps > Android (`com.zainab.nawtin`)**: confirm the
   package name; later add the SHA-1 and SHA-256 fingerprints of the release key
   and of the Play App Signing key (Phase 5 and 7).
3. Download `google-services.json` again if you change anything, and place it at
   `android/app/google-services.json`. It is git-ignored: keep a backup, and put
   a copy on any new machine or CI runner.
4. **Google Cloud console > APIs & Services > Credentials**: restrict the Android
   API key to the package name and the SHA-1 fingerprints.
5. Recommended: **App Check** with Play Integrity.

Full list: [store_checklist.md](store_checklist.md), section 7.

## Phase 3: test on your PC first

Everything here is free and quick to fix.

```powershell
flutter analyze
flutter test                                       # app
cd packages/naw_tin_core; dart test; cd ../..      # engine and AI
cd server; dart test; cd ..                        # server
```

Then the real-sign-in test on your phone, against your PC
([two_device_test_plan.md](two_device_test_plan.md), Round 1):

```powershell
# the server, real sign-in (no NAWTIN_TEST_AUTH)
$env:FIREBASE_PROJECT_ID="nawtin-41c14"; $env:PORT="8090"
cd server; dart run bin/server.dart
# in the log you should see: auth.certs_ok: fetched N Google signing keys
```

Install the debug build that points at your PC, open **Play Online**, and the dot
must turn green. If it shows "Couldn't sign you in", fix Phase 2 now.

Allow port 8090 in the Windows firewall on **private networks only**, and delete
the rule afterwards.

## Phase 4: deploy the server

Follow [deploy_cloud_run.md](deploy_cloud_run.md). In short:

```powershell
.\scripts\deploy_server.ps1 -Region asia-south1 -DryRun    # read the plan
.\scripts\deploy_server.ps1 -Region asia-south1            # type DEPLOY to run it
cd server
dart run tool/check.dart https://<your-service>.run.app    # all four lines PASS
```

Then confirm in the Cloud Run logs that you see `auth.certs_ok`. Write down the
address the script prints, `wss://<host>/ws`: it goes into the release build.

Your gcloud default project is `insightflow-496519`, a different project. The
script and guide always name `nawtin-41c14`; do the same in any command you type.

## Phase 5: upload key and release configuration

1. Create the **upload key** once and back it up (losing it means you cannot
   update the app):
   ```powershell
   keytool -genkey -v -keystore $env:USERPROFILE\nawtin-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Copy `android/key.properties.example` to `android/key.properties` and fill it
   in. Both it and `*.jks` are git-ignored.
3. Print the key's fingerprints and add them to the Firebase Android app:
   `keytool -list -v -keystore $env:USERPROFILE\nawtin-upload.jks -alias upload`.
4. **AdMob:** put your real **app id** in
   `android/app/src/main/AndroidManifest.xml` (`com.google.android.gms.ads.APPLICATION_ID`)
   and your real **rewarded ad unit id** in `lib/services/ads/admob_ads_service.dart`
   (`_androidUnit`). Both are Google *test* ids today. Add your own phone as an
   AdMob test device and never click your own live ads.
5. **Consent:** if you publish in the EEA, UK or Switzerland, add Google's User
   Messaging Platform consent flow before ads load (not built yet) and describe
   it in the privacy policy.
6. **Version:** `pubspec.yaml` `version: 0.1.0+1`. The number after `+` is the
   version code and must go **up with every upload**.

## Phase 6: build and test the release

```powershell
flutter clean
flutter pub get
flutter build appbundle --release `
  --dart-define=ADS=admob `
  --dart-define=NAWTIN_SERVER=wss://<your-service-host>/ws `
  --obfuscate --split-debug-info=build/symbols
```

The upload file is `build/app/outputs/bundle/release/app-release.aab`. **Keep
`build/symbols` for every release** (without it crash reports cannot be read).

| Flag | Why it is required |
|---|---|
| `--dart-define=ADS=admob` | without it the build uses the fake mock ads and every hint looks free |
| `--dart-define=NAWTIN_SERVER=wss://...` | without it the release app reports online play as unavailable; plain `ws://` is refused by design |
| `--obfuscate --split-debug-info` | smaller, harder to read; keep the symbols folder |

For a test on your own phone, build an installable release APK with the same
flags (`flutter build apk --release ...`) and install it. Then run
[two_device_test_plan.md](two_device_test_plan.md) **Round 2**: two phones on
different networks, release builds, the deployed server. Do not go on until
sections 1 to 6 and 8 of that plan pass.

Quick release checks:

- [ ] Settings has **no** "Online test console (debug)".
- [ ] `dart run server/tool/check.dart https://<service>` passes.
- [ ] Airplane mode: the offline game still works.
- [ ] A game on the release build, start to finish, with no ad shown during it.

## Phase 7: Play Console

1. **Create the app** (name Naw Tin; app, not game bundle; free). Enrol in **Play
   App Signing**.
2. After the first upload, copy the **Play App Signing SHA-1/SHA-256** from
   Setup > App signing into the Firebase Android app and into the API key
   restrictions. Anonymous sign-in itself does not depend on it, but the key
   restriction (and App Check, if you turn it on) would otherwise reject
   installs that come from the store.
3. **App content** (all required before you can publish). Use the answers in
   [store_checklist.md](store_checklist.md):
   - Privacy policy URL (the page from Phase 1)
   - Ads: yes
   - Target audience: 13+ / general, not designed for children
   - Content rating questionnaire (users interact: preset emotes only)
   - **Data safety** form (anonymous user id, display name, game activity, ads)
   - Advertising ID declaration: yes
4. **Store listing:** paste the copy from [PLAY_STORE.md](PLAY_STORE.md) (it now
   mentions online play); upload `docs/store/icon_512.png`,
   `feature_graphic_1024x500.png`, and phone screenshots. Take **new screenshots
   of the online lobby and game** from the real app.
5. **Release in stages:**
   1. *Internal testing* (up to 100 testers by email): upload the `.aab`, install
      from the Play link on two phones, repeat the quick release checks.
   2. *Closed testing* with the number of testers and days Google currently asks
      for new personal accounts.
   3. *Production*, ideally with a **staged rollout** (start at 10 to 20%).
6. Answer review questions honestly. If Google asks how a user deletes their
   data: there is no account to delete; uninstalling removes the anonymous
   identity from the phone, and the support email handles log-related requests.

## Phase 8: after launch

| Need | How |
|---|---|
| Is the server up? | `https://<service>/healthz` answers `ok`; set an uptime check and an alert |
| Player reports | search the Cloud Run logs for `report.received` |
| Errors | search for `room.internal_error` / `server.internal_error` |
| Cost | Billing > Reports, and your budget alert |
| A bad server release | roll back to the previous revision ([deploy_cloud_run.md](deploy_cloud_run.md), section 6) |
| Stop everything | `gcloud run services delete naw-tin-server --project nawtin-41c14 --region <region>`; the app then shows "Can't reach the game server" |

Deploys drop live games (rooms are in memory): deploy at a quiet time.

## Updating later

- **Server-only change** (bug fix, tuning): run `deploy_server.ps1` again. Old
  app versions keep working.
- **A change that old apps cannot understand** (new message format): bump
  `protocolVersion` in `packages/naw_tin_core/lib/src/protocol/protocol.dart`.
  Order: (1) deploy a server that still accepts **both** the old and new
  versions (`minProtocolVersion` stays low); (2) publish the new app; (3) once
  most players have updated, raise `minProtocolVersion` and deploy: older apps
  then see the **"Please update the app"** screen instead of a broken game.
- **App-only change:** build with a higher version code and upload.
- Re-run the tests and the quick release checks every time.

## Never

- Never set `NAWTIN_TEST_AUTH` on a deployed server (it refuses to start, and
  `check.dart` fails if it is on).
- Never commit `google-services.json`, `key.properties` or a `.jks` file.
- Never upload an app built without `ADS=admob` and `NAWTIN_SERVER`.
- Never run more than one Cloud Run instance until rooms are stored somewhere
  shared.
- Never rely on the gcloud default project; always pass `--project`.
- Do not lose the upload key or `build/symbols`.

## Not covered

- **iOS:** not prepared (needs an Apple Developer account, a bundle id, its own
  `GoogleService-Info.plist`, and an iOS AdMob app). The code paths exist but
  have not been built or tested on iOS.
- **Web or desktop** builds: not a release target.
- **Matchmaking with strangers, accounts, chat:** not built, on purpose.
