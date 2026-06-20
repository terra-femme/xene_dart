# Load workspace .env and start the Flutter app in DEBUG with the dev menu enabled.
# Same as run_app.ps1, plus --dart-define=XENE_FORCE_DEV_MENU=true so AdminGuard
# is bypassed and /dev/* routes (e.g. AV SANDBOX) are reachable without an admin
# account. DEBUG ONLY — never use this for profile/release/distribution builds.
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

Write-Host "`nStarting Flutter app (Chrome, DEBUG + DEV MENU)..."
Write-Host "  BACKEND_URL=$backendUrl"
Write-Host "  SUPABASE_URL=$supabaseUrl"
Write-Host "  XENE_FORCE_DEV_MENU=true  (debug-only bypass)`n"

flutter run -d chrome `
    "--dart-define=SUPABASE_URL=$supabaseUrl" `
    "--dart-define=SUPABASE_ANON_KEY=$supabaseAnon" `
    "--dart-define=BACKEND_URL=$backendUrl" `
    "--dart-define=AUTH_REDIRECT_URL=$authRedirectUrl" `
    "--dart-define=XENE_FORCE_DEV_MENU=true"
