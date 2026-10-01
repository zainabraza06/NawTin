# Naw Tin - Play Store release notes

Everything you need to take the game from this repository to a Google Play
release. Items marked **TODO (you)** need your accounts or decisions; nothing
here can be done for you from code.

## 1. Before the first release build

| | What | Where |
|---|---|---|
| **TODO (you)** | Pick the final **application id** (currently the placeholder `com.zainab.nawtin`). It can never change after the first upload. | `android/app/build.gradle.kts` (`namespace`, `applicationId`), `ios/` bundle id |
| **TODO (you)** | Create your own **AdMob app** + one *rewarded* ad unit. Replace the Google **test** ids. | Android app id: `android/app/src/main/AndroidManifest.xml` (`APPLICATION_ID`). iOS: `ios/Runner/Info.plist` (`GADApplicationIdentifier`). Ad unit ids: `lib/services/ads/admob_ads_service.dart` (`_androidUnit`, `_iosUnit`) |
| **TODO (you)** | Publish a **privacy policy** URL (required because the app shows ads). | Play Console > App content |
| Done | Launcher icon (adaptive + legacy), INTERNET and AD_ID permissions, app label `Naw Tin` | `assets/icon/`, manifest |
| Done | Fonts and sounds are bundled, so the app works fully offline (ads need a connection) | `assets/` |

Privacy policy draft: [PRIVACY_POLICY.md](PRIVACY_POLICY.md). Tester guide: [PLAYTEST.md](PLAYTEST.md).

Test ads are on by default only when you ask for them:

```
flutter run --dart-define=ADS=admob          # Google test rewarded ads
flutter build appbundle --release --dart-define=ADS=admob
```

Without `--dart-define=ADS=admob` the game uses the built-in **mock** ads
(a timed delay). **A release build for the store must be built with
`ADS=admob`** or players would get every hint and rewind for free-looking
fake ads.

## 2. Signing

1. Create an upload key once (keep the file and passwords somewhere safe; if you
   lose it you cannot update the app):

   ```
   keytool -genkey -v -keystore %USERPROFILE%\nawtin-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Copy `android/key.properties.example` to `android/key.properties` and fill it
   in. Both `key.properties` and `*.jks` are git-ignored.
3. `android/app/build.gradle.kts` already signs release builds with it (and
   falls back to the debug key when the file is missing, so such a build cannot
   be uploaded by accident).
4. Enrol in **Play App Signing** when creating the app in the Play Console.

## 3. Build

```
flutter clean
flutter pub get
flutter test                                   # all tests should pass
flutter build appbundle --release ^
    --dart-define=ADS=admob ^
    --obfuscate --split-debug-info=build/symbols
```

The upload file is `build/app/outputs/bundle/release/app-release.aab`.
Keep `build/symbols` for each release so crash traces can be symbolised.

Version numbers live in `pubspec.yaml` (`version: 0.1.0+1`): the part before
`+` is the name players see, the number after it is the version code and must
go up with every upload.

> This repository was developed without an Android SDK on the build machine, so
> the Gradle changes (release signing, AdMob) have not been compiled here. Run
> one `flutter build appbundle` and a device test before uploading.

## 4. Store listing (copy you can paste)

**App name:** Naw Tin

**Short description (80 chars max):**
`Make three. Eat one. A sharp two-player strategy board game with a smart AI.`

**Full description:**

> Naw Tin is a fast, beautiful board game of lines and nerve. Place your nine
> tokens on a board of three nested squares, then slide them along the lines.
> Make three in a row and you eat one of your opponent's tokens. Leave them with
> two tokens, or no legal move, and you win.
>
> **Play your way**
> - Play against the AI on Easy, Medium or Hard.
> - Pass the phone to a friend for a two-player game.
> - Learn everything in the illustrated How to Play, with live demos.
>
> **Real tactics, not luck**
> - PHUTAS - warn your opponent you are one move from a line.
> - MACHYAS - complete a line and eat a token.
> - BEGI and TREGHI - build a double or triple mill and swing one token to
>   capture again and again.
> - Protected tokens, placement and movement phases, and a turn clock that keeps
>   the game moving.
>
> **Made to feel great**
> - A glowing neon look, smooth animations and haptic feedback.
> - Colour-blind friendly tokens, reduce-motion and screen-reader support.
> - Works offline. Optional rewarded ads unlock hints and a rewind.

**Category:** Games > Board. **Tags:** board game, strategy, two player, puzzle.

## 5. Graphics (generated for you)

Regenerate any time with
`flutter test test/tool/generate_store_assets_test.dart --dart-define=GENERATE_STORE=true`.

| Asset | File |
|---|---|
| Hi-res icon 512x512 | `docs/store/icon_512.png` |
| Feature graphic 1024x500 | `docs/store/feature_graphic_1024x500.png` |
| Phone screenshots 1080x2160 | `docs/store/screenshot_1_home.png` ... `screenshot_4_hint.png` |

Add 7-inch / 10-inch tablet screenshots if you want the listing to show as
tablet-ready (capture them from a tablet emulator).

## 6. Play Console forms

- **Contains ads:** yes (AdMob rewarded ads).
- **Target audience:** choose 13+ / general audience. Do **not** mark the app as
  designed for children: that brings the Families Policy and restricts which ad
  networks you may use.
- **Content rating (IARC questionnaire):** abstract strategy game, no violence,
  no user-generated content, no chat. Expect an "Everyone" style rating; answer
  the ads question truthfully.
- **Data safety:** see [store_checklist.md](store_checklist.md). Online play adds
  an anonymous user id and a display name sent to our server, so the answers
  there replace the ads-only answers that used to be here.
- **Advertising ID declaration:** yes (the manifest declares
  `com.google.android.gms.permission.AD_ID`).
- **Government / financial / health apps:** none of these apply.

## 7. Pre-launch checklist

- [ ] `flutter test` and `flutter analyze` are clean.
- [ ] Replace the AdMob **test** ids, then test real ads on a device with
      *your own* account set as a test device (never click your own live ads).
- [ ] Decide the **placement rule** (see README: seat balance) and set it in
      `lib/main.dart` if you choose the symmetric opening.
- [ ] Play on a low-end phone with **Low-power mode** on and off; check the
      animations stay smooth.
- [ ] Turn on TalkBack and play a game; check the spoken board and announcements.
- [ ] Try airplane mode: the game plays; hints show the "no ad available" message
      and grant nothing.
- [ ] Rotate / background / resume in a vs-AI game: the clock waits while the
      app is away, and resumes.
- [ ] New personal developer accounts must run a **closed test** (currently 12
      testers for 14 days) before applying for production access.

## 8. After launch

- Watch *Android vitals* (crashes, ANRs) and the AdMob fill rate.
- Local-language voice lines: drop the `.wav` files in
  `assets/audio/voice/<language code>/` (see the README there) and flip the
  language to `ready` in `lib/features/home/settings_sheet.dart`.
