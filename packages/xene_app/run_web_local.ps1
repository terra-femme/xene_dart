# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║ Flutter Web Local Network Dev Server                                          ║
# ║ Enables viewing the app on phone/tablet via WiFi on same network             ║
# ║ Usage: ./run_web_local.ps1 [port]  (default port: 8080)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Get Windows machine IP address
$localIP = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast |
    Where-Object { $_.InterfaceAlias -match "WiFi|Ethernet" } |
    Select-Object -First 1).IPAddress

if (-not $localIP) {
    Write-Host "❌ Could not find your machine's IP address. Check WiFi connection." -ForegroundColor Red
    exit 1
}

# Allow custom port via command-line argument
$port = if ($args.Length -gt 0) { $args[0] } else { 8080 }

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║ Flutter Web Dev Server — Local Network                        ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Your machine IP: $localIP" -ForegroundColor Yellow
Write-Host "Port:           $port" -ForegroundColor Yellow
Write-Host ""
Write-Host "🌐 On your phone/tablet (same WiFi):" -ForegroundColor Cyan
Write-Host "   http://$localIP`:$port" -ForegroundColor Cyan
Write-Host ""
Write-Host "ℹ️  Backend:      http://$localIP`:8080/api (or custom port)" -ForegroundColor Gray
Write-Host "ℹ️  Hot Reload:   Press R in terminal after code changes" -ForegroundColor Gray
Write-Host "ℹ️  Usage:        ./run_web_local.ps1 [port]  (default: 8080)" -ForegroundColor Gray
Write-Host ""

# Verify backend is running (optional, check standard port)
$backendResponse = $null
try {
    $backendResponse = Invoke-WebRequest -Uri "http://localhost:8080/config" -TimeoutSec 2 -SkipHttpErrorCheck
} catch {
    # Ignore errors, just checking if backend is there
}

if ($backendResponse -and $backendResponse.StatusCode -eq 200) {
    Write-Host "✅ Local backend detected at http://localhost:8080" -ForegroundColor Green
    $useLocalBackend = $true
} else {
    Write-Host "⚠️  Local backend NOT detected (http://localhost:8080)" -ForegroundColor Yellow
    Write-Host "   Will use production backend at https://xene-backend.yellowwater-2ccd556b.eastus.azurecontainerapps.io" -ForegroundColor Yellow
    Write-Host "   ℹ️  To use local backend, run: ./packages/xene_backend/run_dev.ps1 in another terminal" -ForegroundColor Gray
    $useLocalBackend = $false
}

Write-Host ""

# Supabase credentials (from .env)
$supabaseUrl = "https://zwhabeyrhiqwzzttwfrk.supabase.co"
$supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp3aGFiZXlyaGlxd3p6dHR3ZnJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1NTU0NDMsImV4cCI6MjA5MjEzMTQ0M30.-w5Iuke6u2CKSsCJ3MXsmdkEWQhipBnCak1wOHpQUI4"

# Start dev server
if ($useLocalBackend) {
    Write-Host "🚀 Starting Flutter web (with local backend)..." -ForegroundColor Cyan
    flutter run -d chrome --web-hostname $localIP --web-port $port --dart-define=BACKEND_URL=http://$localIP`:8080 --dart-define=SUPABASE_URL=$supabaseUrl --dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey
} else {
    Write-Host "🚀 Starting Flutter web (with production backend)..." -ForegroundColor Cyan
    flutter run -d chrome --web-hostname $localIP --web-port $port --dart-define=BACKEND_URL=https://xene-backend.yellowwater-2ccd556b.eastus.azurecontainerapps.io --dart-define=SUPABASE_URL=$supabaseUrl --dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey
}
