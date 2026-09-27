# Checks, renders and packages one FitSocial brag output folder.
#
#   ./brag.ps1 -Slug 01-onboarding -PosterAt 2.5 -Slides 5
#
# Expects output/<slug>/composition (the video) and output/<slug>/carousel-src
# (the slides, one per second, the last taken at SlideLast). Writes brag.mp4
# with the poster baked in as frame 0, brag.jpg and carousel/carousel_NN.png.
param(
  [Parameter(Mandatory)] [string] $Slug,
  [double] $PosterAt = 2.5,
  [int] $Slides = 0,
  [double] $SlideLast = -1,
  [switch] $SkipVideo,
  [switch] $SkipCarousel
)
# Native tools write progress to stderr; failures are caught by exit code.
$ErrorActionPreference = 'Continue'
$env:Path += ";$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin"
$hf = Get-ChildItem "$env:TEMP\claude" -Recurse -Filter hyperframes.cmd -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like '*scratchpad\hf\node_modules\.bin*' } | Select-Object -First 1 -ExpandProperty FullName
if (-not $hf) { $hf = 'npx hyperframes' }
$kit = Join-Path $PSScriptRoot '..\kit'
$out = Join-Path $PSScriptRoot "..\output\$Slug"

function Invoke-Hf([string[]] $HfArgs) {
  & $hf @HfArgs 2>$null
  if ($LASTEXITCODE -ne 0) { throw "hyperframes $($HfArgs -join ' ') failed" }
}

if (-not $SkipVideo) {
  Push-Location "$out\composition"
  Copy-Item "$kit\kit.js", "$kit\kit.css" . -Force
  Invoke-Hf @('check', '--samples', '15') | Select-Object -Last 1
  Invoke-Hf @('render', '--quality', 'delivery', '--output', '../brag.mp4') | Select-Object -Last 3
  Pop-Location
  Push-Location $out
  ffmpeg -v error -y -ss $PosterAt -i brag.mp4 -frames:v 1 -q:v 2 brag.jpg
  ffmpeg -v error -y -i brag.mp4 -i brag.jpg -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" `
    -map "[v]" -map '0:a?' -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -c:a copy -movflags +faststart brag.poster.mp4
  Move-Item brag.poster.mp4 brag.mp4 -Force
  ffprobe -v error -show_entries format=duration -of csv=p=0 brag.mp4
  Pop-Location
}

if (-not $SkipCarousel -and $Slides -gt 0) {
  Push-Location "$out\carousel-src"
  Copy-Item "$kit\kit.js", "$kit\kit.css" . -Force
  Invoke-Hf @('check', '--samples', '16') | Select-Object -Last 1
  if (Test-Path snapshots) { Remove-Item -Recurse -Force snapshots }
  $last = if ($SlideLast -ge 0) { $SlideLast } else { ($Slides - 1) + 0.6 }
  $times = @(); for ($i = 0; $i -lt $Slides - 1; $i++) { $times += "$i.6" }; $times += "$last"
  Invoke-Hf @('snapshot', '--at', ($times -join ',')) | Out-Null
  New-Item -ItemType Directory -Force ..\carousel | Out-Null
  $n = 1
  # snapshot adds its own end-of-timeline frame after ours; keep ours.
  Get-ChildItem snapshots -Filter 'frame-*.png' | Sort-Object Name | Select-Object -First $Slides | ForEach-Object {
    Copy-Item $_.FullName ("..\carousel\carousel_{0:D2}.png" -f $n) -Force; $n++
  }
  Pop-Location
  "carousel: $($n - 1) slides"
}
