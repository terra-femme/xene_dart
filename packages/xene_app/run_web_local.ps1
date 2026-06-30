# Flutter Web Local Network Dev Server
# Enables viewing the app on phone/tablet via WiFi on same network
# Usage: ./run_web_local.ps1 [port] [-PerfHud]  (default port: 3000)
#   -PerfHud  Show the on-screen frame-timing overlay (build/raster ms, jank
#             counters) for diagnosing lag on touch devices without DevTools.
#
# Port is pinned to 3000 (not the backend's 8080) so the web origin is STABLE and
# can be added once to Supabase → Authentication → URL Configuration → Redirect
# URLs (the app sends Uri.base.origin as the magic-link redirect on web).
param(
    [int]$Port = 3000,
    [switch]$PerfHud,
    # -Lan: serve on the LAN IP (open on a phone over WiFi) instead of localhost.
    # Web viewing works; magic-link sign-in does NOT over a bare http LAN IP
    # (front it with HTTPS / your travel router). Default = localhost.
    [switch]$Lan
)

# Get all IPv4 addresses excluding virtual adapters
$allIPs = @()
$adapters = Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and
    $_.Name -notmatch 'vEthernet|DockerNAT|Hyper-V|VirtualBox|VMware|WSL|Loopback|Bluetooth'
}
foreach ($adapter in $adapters) {
    $addresses = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
    $allIPs += $addresses
}

# Try to find 192.168.1.x (standard home/small office WiFi) - HIGHEST PRIORITY
$localIP = ($allIPs | Where-Object { $_.IPAddress -match "^192\.168\.1\." } | Select-Object -First 1).IPAddress

# If not found, try other standard ranges (192.168.0.x, 10.x.x.x)
if (-not $localIP) {
    $localIP = ($allIPs | Where-Object { $_.IPAddress -match "^192\.168\.0\." } | Select-Object -First 1).IPAddress
}
if (-not $localIP) {
    $localIP = ($allIPs | Where-Object { $_.IPAddress -match "^10\." } | Select-Object -First 1).IPAddress
}
# Fallback to any 192.168.x.x (excluding 64.x which is virtual, 127.x which is loopback, 169.x which is link-local)
if (-not $localIP) {
    $localIP = ($allIPs | Where-Object {
        $_.IPAddress -match "^192\.168\." -and
        $_.IPAddress -notmatch "^192\.168\.64\.|^192\.168\.127\."
    } | Select-Object -First 1).IPAddress
}
# Last resort: any other IP (but not link-local 169.254.x.x)
if (-not $localIP) {
    $localIP = ($allIPs | Where-Object { $_.IPAddress -notmatch "^169\.254\." } | Select-Object -First 1).IPAddress
}

if (-not $localIP) {
    Write-Host "ERROR: Could not find your machine's IP address. Check WiFi connection." -ForegroundColor Red
    exit 1
}

# Production Supabase credentials (zwhabeyrhiqwzzttwfrk project)
$env:SUPABASE_URL = "https://zwhabeyrhiqwzzttwfrk.supabase.co"
$env:SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp3aGFiZXlyaGlxd3p6dHR3ZnJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1NTU0NDMsImV4cCI6MjA5MjEzMTQ0M30.-w5Iuke6u2CKSsCJ3MXsmdkEWQhipBnCak1wOHpQUI4"

# Port comes from the -Port parameter (positional, default 3000).
$port = $Port

# Hostname the dev server binds to:
#   default -> localhost  (Supabase honors http://localhost, so sign-in works)
#   -Lan    -> the LAN IP (open the web build on a phone over WiFi)
if ($Lan) { $webHost = $localIP } else { $webHost = 'localhost' }
$displayUrl = "http://${webHost}:$port"

# Optional on-screen performance HUD. Passed to `flutter run` below only when
# -PerfHud is set. NOTE: must stay a real array — building it with the
# if-EXPRESSION form ($x = if (...) { @('one') }) collapses a single-element
# array to a scalar STRING, and splatting a string iterates its characters
# (flutter then sees a bare "-" → "Target file '-' not found"). Initialise as an
# array and assign directly inside the if to preserve the array type.
$perfHudArg = @()
if ($PerfHud) {
    $perfHudArg = @('--dart-define=XENE_PERF_HUD=true')
    Write-Host "PerfHud: ON (frame-timing overlay enabled)" -ForegroundColor Magenta
}

Write-Host ""
Write-Host "Flutter Web Dev Server" -ForegroundColor Green
Write-Host ""
if ($Lan) {
    Write-Host "Mode: LAN (-Lan) -- open on a phone over WiFi" -ForegroundColor Yellow
    Write-Host "  Phone URL: $displayUrl" -ForegroundColor Cyan
    Write-Host "  Web viewing works; magic-link SIGN-IN won't over http LAN IP" -ForegroundColor Gray
    Write-Host "  (front it with HTTPS / your travel router for phone sign-in)." -ForegroundColor Gray
} else {
    Write-Host "Mode: localhost (default) -- desktop web + magic-link sign-in" -ForegroundColor Yellow
    Write-Host "  Open in your Chrome: $displayUrl" -ForegroundColor Cyan
    Write-Host "  For a phone, re-run with -Lan (LAN IP: http://${localIP}:$port)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Supabase Redirect URLs must include: $displayUrl" -ForegroundColor Gray
Write-Host "Hot Reload: Press R in terminal after code changes" -ForegroundColor Gray
Write-Host "Usage: ./run_web_local.ps1 [port] [-PerfHud] [-Lan]  (default: 3000)" -ForegroundColor Gray
Write-Host ""

# Verify backend is running (optional, check standard port)
$backendResponse = $null
try {
    $backendResponse = Invoke-WebRequest -Uri "http://localhost:8080/config" -TimeoutSec 2 -SkipHttpErrorCheck
} catch {
    # Ignore errors, just checking if backend is there
}

if ($backendResponse -and $backendResponse.StatusCode -eq 200) {
    Write-Host "OK: Local backend detected at http://localhost:8080" -ForegroundColor Green
    $useLocalBackend = $true
} else {
    Write-Host "WARNING: Local backend NOT detected (http://localhost:8080)" -ForegroundColor Yellow
    Write-Host "Will use production backend at https://xene-backend.yellowwater-2ccd556b.eastus.azurecontainerapps.io" -ForegroundColor Yellow
    Write-Host "To use local backend, run: ./packages/xene_backend/run_dev.ps1 in another terminal" -ForegroundColor Gray
    $useLocalBackend = $false
}

Write-Host ""

# Change to xene_app directory (monorepo structure)
# $PSScriptRoot is packages/xene_app directory, so we're already there
cd $PSScriptRoot

# Start dev server
if ($useLocalBackend) {
    Write-Host "Starting Flutter web (with local backend)..." -ForegroundColor Cyan
    Write-Host "URL: $displayUrl" -ForegroundColor Green
    Write-Host "  (Flutter also auto-opens its own debug window - you can ignore it.)" -ForegroundColor Gray
    $backendUrl = "http://${localIP}:8080"
    & flutter run -d chrome --web-hostname $webHost --web-port $port --dart-define="BACKEND_URL=$backendUrl" --dart-define="SUPABASE_URL=$env:SUPABASE_URL" --dart-define="SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY" $perfHudArg
} else {
    Write-Host "Starting Flutter web (with production backend)..." -ForegroundColor Cyan
    Write-Host "URL: $displayUrl" -ForegroundColor Green
    Write-Host "  (Flutter also auto-opens its own debug window - you can ignore it.)" -ForegroundColor Gray
    & flutter run -d chrome --web-hostname $webHost --web-port $port --dart-define='BACKEND_URL=https://xene-backend.yellowwater-2ccd556b.eastus.azurecontainerapps.io' --dart-define="SUPABASE_URL=$env:SUPABASE_URL" --dart-define="SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY" $perfHudArg
}
