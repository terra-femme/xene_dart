# Run the Flutter web app in PROFILE mode for representative performance testing.
#
# Profile mode uses the optimizing compiler (like release), so what you see is
# close to real production UX — unlike debug mode, which is 5-10x slower and not
# representative. Auth still works because this passes the SAME dart-defines and
# the SAME port (4000) as the debug launch, so the Supabase redirect allowlist
# and backend CORS origin still match.
#
# Notes:
#   - Hot reload is NOT available in profile mode (expected — this is for
#     measuring, not editing). Use the debug launch for iterating on code.
#   - The backend must be running first (packages/xene_backend/run_dev.ps1).
#   - Open DevTools → Performance to profile a specific janky surface.
#
# Mirrors run_app.ps1 (which is debug) but adds --profile and pins --web-port 4000.
$envFile = Join-Path $PSScriptRoot "..\..\\.env"

if (-not (Test-Path $envFile)) {
    Write-Error ".env not found at $envFile"
    exit 1
}

$envVars = @{}
Get-Content $envFile | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "=" } | ForEach-Object {
    $key, $value = $_ -split "=", 2
    $key = $key.Trim()
    $value = $value.Trim()
    if ($key -and $value) {
        $envVars[$key] = $value
    }
}

$supabaseUrl  = $envVars['SUPABASE_URL']
$supabaseAnon = $envVars['SUPABASE_ANON_KEY']

if (-not $supabaseUrl -or -not $supabaseAnon) {
    Write-Error "SUPABASE_URL or SUPABASE_ANON_KEY missing from .env"
    exit 1
}

$backendUrl      = if ($envVars['BACKEND_URL']) { $envVars['BACKEND_URL'] } else { 'http://localhost:8080' }
$authRedirectUrl = if ($envVars['AUTH_REDIRECT_URL']) { $envVars['AUTH_REDIRECT_URL'] } else { 'http://localhost:4000' }

Write-Host "`nStarting Flutter app in PROFILE mode (Chrome, port 4000)..."
Write-Host "  BACKEND_URL=$backendUrl"
Write-Host "  SUPABASE_URL=$supabaseUrl`n"

flutter run -d chrome --profile --web-port 4000 `
    "--dart-define=SUPABASE_URL=$supabaseUrl" `
    "--dart-define=SUPABASE_ANON_KEY=$supabaseAnon" `
    "--dart-define=BACKEND_URL=$backendUrl" `
    "--dart-define=AUTH_REDIRECT_URL=$authRedirectUrl" `
    "--dart-define=XENE_FORCE_DEV_MENU=true"
