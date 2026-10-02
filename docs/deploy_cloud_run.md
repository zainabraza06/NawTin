# Deploying the Naw Tin server to Google Cloud Run

This puts the online server on the internet so two phones anywhere can play. It
uses the same Google project as the app's Firebase sign-in (`nawtin-41c14`).

**Status:** the image builds and runs, and the server passes its smoke test
locally. It has **not been deployed yet**: that needs your Google account,
billing and a decision on the region. Everything below is written to be followed
top to bottom; the one-command version is `scripts/deploy_server.ps1`.

## 0. Before you start

| | |
|---|---|
| **Billing** | Cloud Run needs a billing account on the project. In the Firebase console this means moving `nawtin-41c14` from Spark to the **Blaze** (pay as you go) plan. Set a **budget alert** (Billing > Budgets & alerts) before anything else. |
| **Which account** | `gcloud auth list` should show a Google account that is an Owner/Editor of `nawtin-41c14`. (Your gcloud is currently signed in as `zainabraza1960@gmail.com` with the default project `insightflow-496519`, which is a *different* project. **Never rely on the default project:** every command below passes `--project nawtin-41c14`.) |
| **Tools** | Google Cloud SDK (`gcloud`) and Docker Desktop, both already installed here. Docker must be running. |
| **Region** | Pick the region closest to your players, because every move crosses the network. Examples: `asia-south1` (Mumbai), `europe-west1` (Belgium), `us-central1` (Iowa). The region cannot be changed later without redeploying. |
| **Never** | set `NAWTIN_TEST_AUTH`. The server refuses to start on Cloud Run with it, but do not rely on that. |

## 1. Why these settings

| Setting | Value | Why |
|---|---|---|
| `--max-instances` | **1** | Rooms live in the memory of one server process. With two instances, a player could land on a server that does not know their room. Keep it at 1 until the server stores rooms somewhere shared. The concurrency setting below allows 1000 open sockets (about 500 simultaneous games); real capacity under load has **not been measured**, so watch CPU and memory once players arrive. |
| `--min-instances` | 1 | The server is always warm, so the first player never waits for a cold start and rooms do not disappear because the instance scaled to zero. It costs money while idle (see 7). `0` is fine for early testing. |
| `--no-cpu-throttling` | on | Turn clocks, reconnect windows and room expiry are timers. Without this, Cloud Run slows the CPU between requests and timers can run late. |
| `--concurrency` | 1000 | Each open WebSocket counts as one concurrent request. The default of 80 would turn away the 81st connection. |
| `--timeout` | 3600 | Cloud Run closes a WebSocket after at most an hour. The app reconnects by itself and rejoins its room, so an hour-long game just sees a brief "reconnecting". |
| `--allow-unauthenticated` | on | Cloud Run's own door must be open to the public because the app is not a Google account. Authentication happens **inside** the app protocol: the first message must carry a valid Firebase ID token for project `nawtin-41c14`, or the server closes the socket (4001). |
| `FIREBASE_PROJECT_ID` | `nawtin-41c14` | The server only accepts tokens issued for this project. |
| CPU / memory | 1 vCPU / 512 MiB | The server is a small compiled Dart program. Raise it only if monitoring shows a need. |

## 2. Deploy with the script (recommended)

From the repository root, in PowerShell:

```powershell
.\scripts\deploy_server.ps1 -Region asia-south1 -DryRun   # prints the plan, runs nothing
.\scripts\deploy_server.ps1 -Region asia-south1           # asks you to type DEPLOY
```

It enables the two APIs, creates an Artifact Registry repository, builds the
image from the repository root, pushes it and deploys. At the end it prints the
service URL and the address to give the app, `wss://<host>/ws`. Add
`-MinInstances 0` to save money while testing.

## 3. Deploy by hand (what the script does)

```powershell
$P = "nawtin-41c14"; $R = "asia-south1"        # your region
$IMG = "$R-docker.pkg.dev/$P/naw-tin/server:latest"

gcloud services enable run.googleapis.com artifactregistry.googleapis.com --project $P
gcloud artifacts repositories create naw-tin --repository-format=docker --location=$R --project $P
gcloud auth configure-docker "$R-docker.pkg.dev"

docker build -f server/Dockerfile -t $IMG .          # from the repository root
docker push $IMG

gcloud run deploy naw-tin-server --project $P --region $R --image $IMG `
  --allow-unauthenticated --max-instances=1 --min-instances=1 `
  --no-cpu-throttling --concurrency=1000 --timeout=3600 --cpu=1 --memory=512Mi `
  --set-env-vars FIREBASE_PROJECT_ID=$P
```

## 4. Check that it works

Get the address:

```powershell
gcloud run services describe naw-tin-server --project $P --region $R --format "value(status.url)"
```

Then run the smoke test from the `server` folder:

```powershell
dart run tool/check.dart https://naw-tin-server-xxxxxxxx-el.a.run.app
```

All four lines must say `PASS`:

1. `/healthz` answers `ok`;
2. the WebSocket connects (over `wss://`);
3. a **fake** sign-in token is refused with `unauthorized`/4001: this proves the
   deployed server is not in test mode;
4. an unsupported protocol gets the "please update" refusal (4000).

Then look at the logs (Cloud Console > Cloud Run > naw-tin-server > Logs, or
`gcloud run services logs read naw-tin-server --project $P --region $R --limit 30`)
and make sure you see:

```
auth.certs_ok: fetched N Google signing keys
Naw Tin server listening on :8080 (protocol 1, firebase nawtin-41c14)
```

`auth.certs_failed` means the server cannot reach Google to check sign-ins
(real players would all be refused). It was tested inside the image locally and
passes there.

The smoke test cannot prove **real Firebase sign-in** works, because that needs
the app. That is the first thing in the two-device test plan.

## 5. Point the app at it and build the release

```powershell
flutter build appbundle --release `
  --dart-define=NAWTIN_SERVER=wss://naw-tin-server-xxxxxxxx-el.a.run.app/ws `
  --dart-define=ADS=admob
```

* A release build accepts **`wss://` only**. Without `NAWTIN_SERVER` it reports
  online play as unavailable (the designed "not available in this build" screen).
* `android/app/google-services.json` must be present on the build machine.
* For a quick test on your phone before publishing, you can build an APK the same
  way (`flutter build apk --release --dart-define=...`) and install it.

## 6. Updating, rolling back, stopping

* **Update:** run the script again. It builds, pushes and deploys a new revision.
* **Rooms do not survive a deploy.** The old process receives SIGTERM, closes
  every socket with code 4004 (the app shows "reconnecting"), and the new one
  starts empty. Players then see "the room was closed" and can start a new one.
  Deploy at a quiet time, and tell testers beforehand.
* **Roll back:** `gcloud run revisions list --project $P --region $R --service naw-tin-server`,
  then `gcloud run services update-traffic naw-tin-server --project $P --region $R --to-revisions REVISION=100`.
* **Stop completely (stops the charges):**
  `gcloud run services delete naw-tin-server --project $P --region $R`.
  Online play in the app then shows the "can't reach the game server" screen.

## 7. Cost

Cloud Run bills for the CPU and memory the instance holds, plus requests and
network. With `--min-instances=1` and `--no-cpu-throttling` one small instance
is billed around the clock, which is the main cost; with `--min-instances=0` you
pay only while someone is connected. The first months are usually small, but
**check the current price list for your region** (cloud.google.com/run/pricing)
and the budget alert from step 0, rather than trusting a number written here.

Cheapest safe start: `-MinInstances 0` for closed testing, then raise it to 1
when real players arrive.

## 8. Day-to-day operation

| Need | How |
|---|---|
| Is it up? | `https://<url>/healthz` answers `ok` |
| Live logs | Cloud Run > naw-tin-server > Logs |
| Reports from players | search the logs for `report.received` (room, both anonymous ids, reason, time) |
| Errors | search for `room.internal_error` or `server.internal_error` |
| Alert on trouble | Cloud Monitoring > Alerting: instance restarts, 5xx rate, container memory |
| Tune the game | set env vars on the service, for example `NAWTIN_TURN_SECONDS`, `NAWTIN_RECONNECT_SECONDS`, `NAWTIN_ROOM_MINUTES` (see `server/README.md`); a change makes a new revision, and new rooms use it |

## 9. Security notes

* The server needs **no secrets**: it verifies tokens with Google's public keys.
  There is nothing to leak from the container or the repository.
* The public endpoint is protected by: Firebase token required on the first
  message (5-second deadline), per-user and per-IP rate limits, a 4 KB frame cap,
  and a ceiling of one instance, which also caps your bill under a flood.
* Recommended next: Firebase **App Check** with Play Integrity, so only the real
  app can obtain tokens (listed in [store_checklist.md](store_checklist.md)).
* Cloud Run terminates TLS for you, so the server itself speaks plain HTTP/WS
  inside Google's network and clients only ever see `https://` / `wss://`.

## 10. Troubleshooting

| Symptom | Likely cause |
|---|---|
| App says "Couldn't sign you in" | Anonymous sign-in not enabled in the Firebase console; wrong or missing `google-services.json`; or the server's `FIREBASE_PROJECT_ID` is not the project the app is signed into |
| App says "Can't reach the game server" | wrong `NAWTIN_SERVER` address in the build; the service was deleted; the region/URL was mistyped |
| `check.dart` fails step 3 | the deployed server has test mode on, which Cloud Run should refuse; look at the logs, then redeploy without `NAWTIN_TEST_AUTH` |
| Players land in different rooms | more than one instance is running: check `--max-instances=1` |
| Moves feel slow | region far from players; redeploy in a closer region |
| `auth.certs_failed` in logs | the instance cannot reach `www.googleapis.com`; check any VPC/egress settings (none by default) |
| `docker push` is denied | run `gcloud auth configure-docker <region>-docker.pkg.dev` again, and confirm the repository exists in that region |
