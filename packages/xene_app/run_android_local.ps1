# Flutter Native Android Dev Runner (Amazon Fire / Android tablet, over USB)
# Builds and runs the app NATIVELY on a connected Android device - the honest way
# to judge performance, unlike the web build in a tablet browser (run_web_local.ps1)
# or the PC-side emulator.
#
# Usage: ./run_android_local.ps1 [-PerfHud] [-DeviceId <serial>] [-Mode profile|debug|release] [-LocalBackend]
#   -PerfHud       On-screen frame-timing overlay (build/raster ms, jank counters)
#                  for diagnosing lag on a touch device with no DevTools.
#   -DeviceId      Target a specific device serial. Default: first authorized
#                  Android device adb reports.
#   -Mode          Build mode. Default: profile - release-level performance while
#                  the HUD + debugPrint logs still work. Use this for perf testing.
#                  (debug is artificially slow and would mislead you.)
#   -LocalBackend  Point at your PC's LAN backend (http://<lan-ip>:8080) instead of
#                  production. Requires cleartext HTTP allowed in the Android
#                  manifest AND the backend running AND the tablet on the same WiFi.
#                  Default is the production HTTPS backend - no cleartext caveat,
#                  always has data, best for a clean perf test.
param(
    [switch]$PerfHud,
    [string]$DeviceId,
    [ValidateSet('profile', 'debug', 'release')]
    [string]$Mode = 'profile',
    [switch]$LocalBackend
)

# Production Supabase credentials (zwhabeyrhiqwzzttwfrk project) - same as web runner.
$env:SUPABASE_URL = "https://zwhabeyrhiqwzzttwfrk.supabase.co"
$env:SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp3aGFiZXlyaGlxd3p6dHR3ZnJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1NTU0NDMsImV4cCI6MjA5MjEzMTQ0M30.-w5Iuke6u2CKSsCJ3MXsmdkEWQhipBnCak1wOHpQUI4"

# Locate adb: prefer the SDK install, fall back to PATH.
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { $adb = "adb" }

# Pick a device if one wasn't named. Match only lines ending in "<TAB>device"
# (an authorized, ready device) - NOT "unauthorized" or "offline".
if (-not $DeviceId) {
    $deviceLine = & $adb devices | Select-String -Pattern '\bdevice$' | Select-Object -First 1
    if ($deviceLine) {
        $DeviceId = ($deviceLine.ToString() -split '\s+')[0]
    }
}

if (-not $DeviceId) {
    Write-Host "ERROR: No authorized Android device found." -ForegroundColor Red
    Write-Host "  - Plug the tablet in via a DATA USB cable" -ForegroundColor Gray
    Write-Host "  - Enable ADB/USB debugging (Settings > Device Options > Developer Options)" -ForegroundColor Gray
    Write-Host "  - Tap 'Allow' on the debugging prompt, then re-run." -ForegroundColor Gray
    Write-Host "  - Check it's seen: `"$adb`" devices" -ForegroundColor Gray
    exit 1
}

# Choose backend. Default production (HTTPS, always reachable, no cleartext issue).
$prodBackend = 'https://xene-backend.yellowwater-2ccd556b.eastus.azurecontainerapps.io'
if ($LocalBackend) {
    # Discover this machine's LAN IP so the tablet (on the same WiFi) can reach the
    # backend running on the PC. Same adapter-filtering logic as run_web_local.ps1.
    $allIPs = @()
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and
        $_.Name -notmatch 'vEthernet|DockerNAT|Hyper-V|VirtualBox|VMware|WSL|Loopback|Bluetooth'
    }
    foreach ($adapter in $adapters) {
        $allIPs += Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
    }
    $localIP = ($allIPs | Where-Object { $_.IPAddress -match "^192\.168\.1\." } | Select-Object -First 1).IPAddress
    if (-not $localIP) { $localIP = ($allIPs | Where-Object { $_.IPAddress -match "^192\.168\.0\." } | Select-Object -First 1).IPAddress }
    if (-not $localIP) { $localIP = ($allIPs | Where-Object { $_.IPAddress -match "^10\." } | Select-Object -First 1).IPAddress }
    if (-not $localIP) { $localIP = ($allIPs | Where-Object { $_.IPAddress -notmatch "^169\.254\." } | Select-Object -First 1).IPAddress }

    if (-not $localIP) {
        Write-Host "ERROR: -LocalBackend set but couldn't find a LAN IP. Check WiFi." -ForegroundColor Red
        exit 1
    }
    $backendUrl = "http://${localIP}:8080"
    Write-Host "Backend: LOCAL ($backendUrl)" -ForegroundColor Yellow
    Write-Host "  NOTE: native Android blocks cleartext HTTP by default. If the feed" -ForegroundColor Yellow
    Write-Host "  is empty, the manifest needs usesCleartextTraffic enabled for this IP." -ForegroundColor Yellow
} else {
    $backendUrl = $prodBackend
    Write-Host "Backend: PRODUCTION ($backendUrl)" -ForegroundColor Green
}

# Optional on-screen performance HUD. NOTE: must stay a real array - building it
# with the if-EXPRESSION form ($x = if (...) { @('one') }) collapses a single-element
# array to a scalar STRING, and splatting a string iterates its characters (flutter
# then sees a bare "-" -> "Target file '-' not found"). Initialise as an array and
# assign inside the if to preserve the array type.
$perfHudArg = @()
if ($PerfHud) {
    $perfHudArg = @('--dart-define=XENE_PERF_HUD=true')
    Write-Host "PerfHud: ON (frame-timing overlay enabled)" -ForegroundColor Magenta
}

Write-Host ""
Write-Host "Flutter Native Android Runner" -ForegroundColor Green
Write-Host "Device : $DeviceId" -ForegroundColor Yellow
Write-Host "Mode   : $Mode" -ForegroundColor Yellow
Write-Host "Hot Reload: press R in this terminal (debug mode); profile is restart-only" -ForegroundColor Gray
Write-Host "First build downloads Gradle deps + compiles native ARM - give it a few minutes." -ForegroundColor Gray
Write-Host ""

# $PSScriptRoot is packages/xene_app - run from there (monorepo root resolves below it).
cd $PSScriptRoot

# --$Mode expands to --profile / --debug / --release.
& flutter run --$Mode -d $DeviceId --dart-define="BACKEND_URL=$backendUrl" --dart-define="SUPABASE_URL=$env:SUPABASE_URL" --dart-define="SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY" $perfHudArg
