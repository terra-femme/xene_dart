# Load workspace .env and start dart_frog dev
$envFile = Join-Path $PSScriptRoot "..\..\\.env"

if (-not (Test-Path $envFile)) {
    Write-Error ".env not found at $envFile"
    exit 1
}

Get-Content $envFile | Where-Object { $_ -notmatch "^\s*#" -and $_ -match "=" } | ForEach-Object {
    $key, $value = $_ -split "=", 2
    $key = $key.Trim()
    $value = $value.Trim()
    if ($key) {
        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        Write-Host "  SET $key"
    }
}

# Free port 8080 if already in use
$existing = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "`n  Killing existing process on port 8080 (PID $($existing.OwningProcess))..."
    Stop-Process -Id $existing.OwningProcess -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

Write-Host "`nStarting dart_frog dev...`n"
dart_frog dev
