<#
.SYNOPSIS
  Builds the Naw Tin server image and deploys it to Google Cloud Run.

.DESCRIPTION
  Follows docs/deploy_cloud_run.md. It ALWAYS passes --project explicitly (your
  gcloud default project may be a different one), shows every command first, and
  waits for you to type DEPLOY. Nothing is created or changed before that.

.EXAMPLE
  .\scripts\deploy_server.ps1 -Region asia-south1 -DryRun     # just print the plan
  .\scripts\deploy_server.ps1 -Region asia-south1             # really deploy
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Region,
  [string]$Project = 'nawtin-41c14',
  [string]$Service = 'naw-tin-server',
  [string]$Repo = 'naw-tin',
  [int]$MinInstances = 1,
  [switch]$DryRun,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'

# Rooms live in one instance's memory, so there must be exactly one instance.
$MaxInstances = 1

$repoRoot = Split-Path -Parent $PSScriptRoot
$gcloud = (Get-Command gcloud -ErrorAction SilentlyContinue).Source
if (-not $gcloud) {
  $fallback = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
  if (Test-Path $fallback) { $gcloud = $fallback } else { throw 'gcloud was not found. Install the Google Cloud SDK first.' }
}

$image = "$Region-docker.pkg.dev/$Project/$Repo/server:latest"

$plan = @(
  @{ what = 'Enable the Cloud Run and Artifact Registry APIs'; cmd = @($gcloud, 'services', 'enable', 'run.googleapis.com', 'artifactregistry.googleapis.com', '--project', $Project) },
  @{ what = 'Create the image repository (skipped if it exists)'; cmd = @($gcloud, 'artifacts', 'repositories', 'create', $Repo, '--repository-format=docker', "--location=$Region", '--project', $Project); optional = $true },
  @{ what = 'Let Docker push to Artifact Registry'; cmd = @($gcloud, 'auth', 'configure-docker', "$Region-docker.pkg.dev", '--quiet') },
  @{ what = 'Build the image (from the repository root)'; cmd = @('docker', 'build', '-f', 'server/Dockerfile', '-t', $image, '.'); cwd = $repoRoot },
  @{ what = 'Push the image'; cmd = @('docker', 'push', $image) },
  @{ what = 'Deploy to Cloud Run'; cmd = @(
      $gcloud, 'run', 'deploy', $Service,
      '--project', $Project, '--region', $Region,
      '--image', $image,
      '--allow-unauthenticated',                # players sign in inside the app (Firebase), not at the Cloud Run door
      "--max-instances=$MaxInstances",           # rooms are in memory: never more than one instance
      "--min-instances=$MinInstances",
      '--no-cpu-throttling',                     # turn clocks and reconnect timers must keep running
      '--concurrency=1000',                      # every open WebSocket counts as a concurrent request
      '--timeout=3600',                          # longest WebSocket lifetime; the app reconnects by itself
      '--cpu=1', '--memory=512Mi',
      '--set-env-vars', "FIREBASE_PROJECT_ID=$Project"
    ) }
)

Write-Host ''
Write-Host "Project : $Project"
Write-Host "Region  : $Region"
Write-Host "Service : $Service  (min $MinInstances, max $MaxInstances instance)"
Write-Host "Image   : $image"
Write-Host ''
$n = 1
foreach ($step in $plan) {
  Write-Host ("{0}. {1}" -f $n, $step.what)
  Write-Host ('     ' + ($step.cmd -join ' ')) -ForegroundColor DarkGray
  $n++
}
Write-Host ''
Write-Host 'Not set, on purpose: NAWTIN_TEST_AUTH (fake tokens). The server refuses to start with it on Cloud Run.' -ForegroundColor Yellow
Write-Host 'Cloud Run needs a billing account on the project (Firebase Blaze plan). A running instance costs money.' -ForegroundColor Yellow
Write-Host ''

if ($Project -ne 'nawtin-41c14') {
  Write-Host "NOTE: the project is '$Project', not the Naw Tin Firebase project 'nawtin-41c14'. Tokens from the app are checked against FIREBASE_PROJECT_ID, so they must match." -ForegroundColor Yellow
}

if ($DryRun) { Write-Host 'Dry run: nothing was executed.'; return }

if (-not $Yes) {
  $answer = Read-Host 'Type DEPLOY to run these steps'
  if ($answer -ne 'DEPLOY') { Write-Host 'Cancelled. Nothing was changed.'; return }
}

foreach ($step in $plan) {
  Write-Host ''
  Write-Host ">> $($step.what)" -ForegroundColor Cyan
  $exe = $step.cmd[0]
  $argList = $step.cmd[1..($step.cmd.Count - 1)]
  if ($step.cwd) { Push-Location $step.cwd }
  try {
    & $exe @argList
    $code = $LASTEXITCODE
  } finally {
    if ($step.cwd) { Pop-Location }
  }
  if ($code -ne 0) {
    if ($step.optional) { Write-Host '   (continuing: that step is allowed to fail, for example "already exists")' -ForegroundColor DarkGray; continue }
    throw "Step failed (exit code $code): $($step.what)"
  }
}

$url = & $gcloud run services describe $Service --project $Project --region $Region --format 'value(status.url)'
Write-Host ''
Write-Host "Deployed: $url" -ForegroundColor Green
Write-Host "App server address (release builds): wss://$(([uri]$url).Host)/ws"
Write-Host ''
Write-Host 'Next: dart run server/tool/check.dart ' $url
