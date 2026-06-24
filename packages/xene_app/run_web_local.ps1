# Flutter Web Local Network Dev Server
# Enables viewing the app on phone/tablet via WiFi on same network
# Usage: ./run_web_local.ps1 [port]  (default port: 8080)

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

# Allow custom port via command-line argument
$port = if ($args.Length -gt 0) { $args[0] } else { 8080 }

Write-Host ""
Write-Host "Flutter Web Dev Server - Local Network" -ForegroundColor Green
Write-Host ""
Write-Host "Your machine IP: $localIP" -ForegroundColor Yellow
Write-Host "Port: $port" -ForegroundColor Yellow
Write-Host ""
Write-Host "On your phone/tablet (same WiFi):" -ForegroundColor Cyan
Write-Host "  http://${localIP}:$port" -ForegroundColor Cyan
Write-Host ""
Write-Host "Backend: http://${localIP}:8080/api (or custom port)" -ForegroundColor Gray
Write-Host "Hot Reload: Press R in terminal after code changes" -ForegroundColor Gray
Write-Host "Usage: ./run_web_local.ps1 [port]  (default: 8080)" -ForegroundColor Gray
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
    Write-Host "Open in browser: http://${localIP}:$port" -ForegroundColor Green
    $backendUrl = "http://${localIP}:8080"
    & flutter run -d chrome --web-hostname ${localIP} --web-port $port --dart-define="BACKEND_URL=$backendUrl" --dart-define="SUPABASE_URL=$env:SUPABASE_URL" --dart-define="SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY"
} else {
    Write-Host "Starting Flutter web (with production backend)..." -ForegroundColor Cyan
    Write-Host "Open in browser: http://${localIP}:$port" -ForegroundColor Green
    & flutter run -d chrome --web-hostname ${localIP} --web-port $port --dart-define='BACKEND_URL=https://xene-backend.yellowwater-2ccd556b.eastus.azurecontainerapps.io' --dart-define="SUPABASE_URL=$env:SUPABASE_URL" --dart-define="SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY"
}
