# Builds a release APK and ships it to testers via Firebase App Distribution.
#
# Why this exists instead of emailing an APK: a raw sideloaded APK trips Play
# Protect on the tester's device. FitSocial requests ACCESS_BACKGROUND_LOCATION,
# BODY_SENSORS and the health.READ_* group, which is the exact permission shape
# Play Protect's real-time scanner blocks for an unknown signing certificate.
# App Distribution installs through a trusted channel, so the scanner leaves it
# alone and no tester has to switch their malware protection off.
#
# One-time setup, in this order:
#   1. Enable App Distribution in the console (Release & Monitor > App
#      Distribution > Get started) - the API 404s on this project until you do.
#   2. Create a tester group there. Its *group alias* is what -Groups wants,
#      not the display name.
#
# Usage, from fitsocial_app/:
#   powershell -ExecutionPolicy Bypass -File tool/distribute.ps1 -Groups testers
#   powershell -ExecutionPolicy Bypass -File tool/distribute.ps1 -Testers "a@b.com,c@d.com"
#   powershell -ExecutionPolicy Bypass -File tool/distribute.ps1 -Groups testers -SkipBuild
#
# -SkipBuild uploads whatever is already in build/, for when you have just
# built and only want to re-send it.

param(
    [string]$Groups,
    [string]$Testers,
    [string]$Notes,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$appRoot = Split-Path -Parent $PSScriptRoot
$appId   = "1:801328750075:android:50ea43d63351911a5dff5e"
$apk     = Join-Path $appRoot "build\app\outputs\flutter-apk\app-release.apk"

if (-not $Groups -and -not $Testers) {
    throw "Give it someone to send to: -Groups <alias> or -Testers <comma,separated,emails>"
}

if (-not $SkipBuild) {
    Push-Location $appRoot
    try {
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk --release failed" }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $apk)) {
    throw "No release APK at $apk. Drop -SkipBuild, or run 'flutter build apk --release' first."
}

# Refuse to ship a debug-signed build. This is the failure that started all of
# this: with no android/key.properties the release build silently falls back to
# the debug certificate, installs fine locally, and is blocked on the tester's
# phone. Catch it here rather than after the upload.
$buildTools = Get-ChildItem "$env:LOCALAPPDATA\Android\sdk\build-tools" -Directory |
              Sort-Object Name -Descending | Select-Object -First 1
$apksigner = Join-Path $buildTools.FullName "apksigner.bat"
if (Test-Path $apksigner) {
    $certs = & $apksigner verify --print-certs $apk 2>&1 | Out-String
    if ($certs -match "CN=Android Debug") {
        throw "This APK is signed with the Android debug key. android/key.properties is missing or not being picked up - testers will hit 'App blocked to protect your device'."
    }
    Write-Output "Signing  -> OK, not the debug certificate"
} else {
    Write-Warning "apksigner not found; skipping the debug-signature check."
}

# Keep a versioned copy and its mapping file, same as package_apk.ps1.
& (Join-Path $PSScriptRoot "package_apk.ps1")

if (-not $Notes) {
    $sha = (git -C $appRoot rev-parse --short HEAD 2>$null)
    $subject = (git -C $appRoot log -1 --format=%s 2>$null)
    $Notes = if ($sha) { "$sha $subject" } else { "Build from $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
}

$fbArgs = @("appdistribution:distribute", $apk, "--app", $appId, "--release-notes", $Notes)
if ($Groups)  { $fbArgs += @("--groups", $Groups) }
if ($Testers) { $fbArgs += @("--testers", $Testers) }

Write-Output "Uploading to App Distribution..."
& firebase @fbArgs
if ($LASTEXITCODE -ne 0) { throw "App Distribution upload failed" }
