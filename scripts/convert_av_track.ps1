# convert_av_track.ps1 — producer step between the AV lab and the dashboard.
#
# Takes a <name>.avtrack.zip exported by the visualizer's "Save Track" panel
# (WAV crops + track.json [+ chart.json]), transcodes every WAV to mp3 with
# ffmpeg, and leaves a folder ready to drag into Dashboard > AV Tracks.
#
# Usage (from anywhere):
#   powershell -File C:\Users\aznkr\Documents\Fun_Apps\xene\xene_dart\scripts\convert_av_track.ps1 -Zip "C:\Downloads\my-track.avtrack.zip"
#
# Requires: ffmpeg on PATH (winget install Gyan.FFmpeg)

param(
    [Parameter(Mandatory = $true)]
    [string]$Zip,

    # 192kbps is transparent enough for a 30s visualizer clip (~720KB/file)
    [string]$Bitrate = '192k'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Zip)) {
    Write-Error "Zip not found: $Zip"
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found on PATH. Install with: winget install Gyan.FFmpeg"
}

$zipItem = Get-Item $Zip
$outDir = Join-Path $zipItem.DirectoryName ($zipItem.BaseName -replace '\.avtrack$', '')
Write-Host "[convert_av_track] extracting $($zipItem.Name) -> $outDir"

if (Test-Path $outDir) {
    Write-Error "Output folder already exists: $outDir (delete it first so stale files can't mix in)"
}
Expand-Archive -Path $Zip -DestinationPath $outDir

$wavs = Get-ChildItem $outDir -Filter *.wav
if ($wavs.Count -eq 0) {
    Write-Error "No WAV files inside the zip — is this really a lab export?"
}

foreach ($wav in $wavs) {
    $mp3 = [System.IO.Path]::ChangeExtension($wav.FullName, '.mp3')
    Write-Host "[convert_av_track] $($wav.Name) -> $([System.IO.Path]::GetFileName($mp3)) @ $Bitrate"
    & ffmpeg -hide_banner -loglevel error -y -i $wav.FullName -codec:a libmp3lame -b:a $Bitrate $mp3
    if ($LASTEXITCODE -ne 0) {
        Write-Error "ffmpeg failed on $($wav.Name) (exit $LASTEXITCODE)"
    }
    Remove-Item $wav.FullName -Confirm:$false
}

Write-Host ""
Write-Host "[convert_av_track] done. Upload the contents of this folder in Dashboard > AV Tracks:"
Write-Host "  $outDir"
Get-ChildItem $outDir | ForEach-Object { Write-Host "  - $($_.Name)" }
