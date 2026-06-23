# Load workspace .env and .env.local (local overrides workspace)
# .env.local is for local development secrets and should NOT be committed.
$envFile = Join-Path $PSScriptRoot "..\..\\.env"
$envLocalFile = Join-Path $PSScriptRoot ".\.env.local"

if (-not (Test-Path $envFile)) {
    Write-Error ".env not found at $envFile"
    exit 1
}

Write-Host "Loading environment from: $envFile"
Get-Content $envFile | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "=" } | ForEach-Object {
    $key, $value = $_ -split "=", 2
    $key = $key.Trim()
    $value = $value.Trim()
    if ($key) {
        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

# Load .env.local if it exists (overrides .env)
if (Test-Path $envLocalFile) {
    Write-Host "Loading local overrides from: $envLocalFile"
    Get-Content $envLocalFile | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "=" } | ForEach-Object {
        $key, $value = $_ -split "=", 2
        $key = $key.Trim()
        $value = $value.Trim()
        if ($key) {
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
            Write-Host "  OVERRIDE $key = $value"
        }
    }
} else {
    Write-Host "Note: .env.local not found (optional for local development)"
}

# Print what we loaded
Write-Host "`nEnvironment variables set:"
@("XENE_ENV", "ALLOWED_ORIGINS") | ForEach-Object {
    $val = [System.Environment]::GetEnvironmentVariable($_)
    if ($val) {
        Write-Host "  $_ = $val"
    }
}

# Free port 8080 if already in use
$existing = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "`n  Killing existing process on port 8080 (PID $($existing.OwningProcess))..."
    Stop-Process -Id $existing.OwningProcess -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

# Self-heal PATH: `dart pub global activate` does NOT persist its bin dir to the
# Windows PATH, so a freshly launched terminal may not resolve `dart_frog`. If it
# is not on PATH, prepend the pub global bin for THIS session (also covers melos).
if (-not (Get-Command dart_frog -ErrorAction SilentlyContinue)) {
    $pubBin = Join-Path $env:LOCALAPPDATA "Pub\Cache\bin"
    if (Test-Path (Join-Path $pubBin "dart_frog.bat")) {
        $env:Path = "$pubBin;$env:Path"
        Write-Host "  PATH: prepended $pubBin (dart_frog was not on PATH)"
    } else {
        Write-Error "dart_frog not found and $pubBin\dart_frog.bat is missing. Run: dart pub global activate dart_frog_cli"
        exit 1
    }
}

Write-Host "`nStarting dart_frog dev...`n"
dart_frog dev
