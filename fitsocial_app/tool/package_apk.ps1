# Copies the release APK to a shareable, versioned filename.
#
# Flutter always writes build/app/outputs/flutter-apk/app-release.apk, and the
# name is not configurable: listApkPaths() in flutter_tools/lib/src/android/
# gradle.dart hardcodes "app" into the expected filename, and findApkFilesModule
# aborts the build when that exact file is missing. Setting archivesName in
# Gradle renames the artifact and breaks `flutter build apk` on the very last
# step. So rename a *copy* afterwards and leave Flutter's output in place —
# `flutter install` and `flutter run --release` keep working.
#
# Usage, from fitsocial_app/:
#   flutter build apk --release
#   powershell -ExecutionPolicy Bypass -File tool/package_apk.ps1
#
# Also stashes mapping.txt next to the APK. Without the mapping file matching
# the exact build, every R8-obfuscated crash report from a tester is unreadable,
# and the next build overwrites it.

$ErrorActionPreference = "Stop"

$appRoot = Split-Path -Parent $PSScriptRoot
$apk     = Join-Path $appRoot "build\app\outputs\flutter-apk\app-release.apk"
$mapping = Join-Path $appRoot "build\app\outputs\mapping\release\mapping.txt"
$outDir  = Join-Path $appRoot "dist"

if (-not (Test-Path $apk)) {
    throw "No release APK at $apk. Run 'flutter build apk --release' first."
}

# version: 1.0.0+2  ->  name FitSocial-1.0.0+2.apk
$pubspec = Get-Content (Join-Path $appRoot "pubspec.yaml")
$match = $pubspec | Select-String -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $match) { throw "No 'version:' line found in pubspec.yaml" }
$version = $match.Matches[0].Groups[1].Value.Trim()

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$target = Join-Path $outDir "FitSocial-$version.apk"
Copy-Item $apk $target -Force
Write-Output "APK      -> $target  ($([math]::Round((Get-Item $target).Length / 1MB, 1)) MB)"

if (Test-Path $mapping) {
    $mapTarget = Join-Path $outDir "mapping-$version.txt"
    Copy-Item $mapping $mapTarget -Force
    Write-Output "mapping  -> $mapTarget"
} else {
    Write-Warning "No mapping.txt found. Crash reports from this build will not be deobfuscatable."
}
