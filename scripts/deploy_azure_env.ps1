# Azure Container Apps Deployment Script
# Sets environment variables for xene_backend deployment
#
# Usage: .\deploy_azure_env.ps1 -ResourceGroup "xene-rg" -ContainerApp "xene-backend" -Environment "production"
#
# Prerequisites:
#   - Azure CLI installed and authenticated: az login
#   - Required role: Contributor or higher on the resource group
#
# Note: Secrets (API keys, tokens) should be fetched from Azure Key Vault or provided interactively

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$ContainerApp,

    [Parameter(Mandatory=$false)]
    [string]$Environment = "production",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [switch]$Interactive
)

Write-Host "Azure Container Apps Environment Configuration" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# Environment variables configuration
$envVars = @{
    # ============ XENE DEPLOYMENT CONFIG ============
    "XENE_ENV" = $Environment

    # ============ YOUTUBE API CONFIG ============
    # Set batch size to 300 to refresh all ~300 artists every 12 hours
    # Default 10 causes 15-day staleness; 300 ensures fresh content
    "YOUTUBE_REFRESH_BATCH_SIZE" = "300"

    # ============ CORS SECURITY ============
    # CRITICAL: Set to your production domain(s)
    # Format: comma-separated list (e.g., "https://xene.app,https://www.xene.app")
    # If empty: production will FAIL CLOSED (rejects all cross-origin requests)
    "ALLOWED_ORIGINS" = "https://xene.app,https://www.xene.app"

    # ============ SUPABASE CONFIG ============
    # Get from Supabase dashboard: Settings → API
    # SUPABASE_URL: Project URL (e.g., https://xxxxx.supabase.co)
    # SUPABASE_SERVICE_KEY: Service Role key (has full DB access, keep secret)
    "SUPABASE_URL" = ""
    "SUPABASE_SERVICE_KEY" = ""

    # ============ OAUTH & API CREDENTIALS ============
    # SoundCloud: https://soundcloud.com/you/apps → create app
    "SC_CLIENT_ID" = ""
    "SC_CLIENT_SECRET" = ""

    # Twitch Helix: https://dev.twitch.tv/console/apps → create app
    "TWITCH_CLIENT_ID" = ""
    "TWITCH_CLIENT_SECRET" = ""

    # Instagram: https://developers.facebook.com/apps → create app
    "IG_APP_ID" = ""
    "IG_APP_SECRET" = ""
    "IG_REDIRECT_URI" = "https://xene-backend.azurecontainerapps.io/auth/instagram/callback"

    # Beatport: username/password (only needed if Beatport enabled)
    "BEATPORT_USERNAME" = ""
    "BEATPORT_PASSWORD" = ""

    # ============ LLM & DISCOVERY ============
    # Gemini API: https://ai.google.dev/tutorials/setup
    # Format: comma-separated list of API keys (for key rotation)
    "GEMINI_API_KEY" = ""

    # ============ TOKEN ENCRYPTION ============
    # CRITICAL: Generate with: openssl rand -hex 16 (or python -c "import secrets; print(secrets.token_hex(16))")
    # Must be exactly 32 hex characters (16 bytes)
    "TOKEN_ENCRYPTION_KEY" = ""

    # ============ ADMIN ACCESS ============
    # CRITICAL: Random secret for /admin/poll endpoint
    # Generate: openssl rand -base64 32 (or create strong random string)
    "ADMIN_SECRET" = ""

    # ============ FRONTEND INTEGRATION ============
    # URL of the Flutter web app (for CORS allowlist)
    "FRONTEND_URL" = "https://xene.app"

    # ============ SCHEDULER CONFIG ============
    # Set to 'true' to run publication RSS poller on startup
    # (Otherwise runs only on cron schedule)
    "PUBLICATION_STARTUP_POLL" = "false"
}

Write-Host "Configuration Summary:" -ForegroundColor Yellow
Write-Host "  Resource Group:    $ResourceGroup"
Write-Host "  Container App:     $ContainerApp"
Write-Host "  Environment:       $Environment"
Write-Host "  Total Env Vars:    $($envVars.Count)"
Write-Host ""

# Check for empty required variables
$requiredVars = @("SUPABASE_URL", "SUPABASE_SERVICE_KEY", "SC_CLIENT_ID", "SC_CLIENT_SECRET",
                  "TOKEN_ENCRYPTION_KEY", "ADMIN_SECRET", "GEMINI_API_KEY")

$missingVars = @()
foreach ($var in $requiredVars) {
    if ([string]::IsNullOrWhiteSpace($envVars[$var])) {
        $missingVars += $var
    }
}

if ($missingVars.Count -gt 0) {
    Write-Host "⚠️  Missing Required Variables:" -ForegroundColor Yellow
    foreach ($var in $missingVars) {
        Write-Host "   - $var" -ForegroundColor Red
    }
    Write-Host ""

    if ($Interactive) {
        Write-Host "Enter values for missing variables (or press Enter to skip):" -ForegroundColor Cyan
        foreach ($var in $missingVars) {
            $value = Read-Host "  $var"
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $envVars[$var] = $value
            }
        }
    } else {
        Write-Host "ERROR: Cannot proceed with missing required variables." -ForegroundColor Red
        Write-Host "Run with -Interactive flag to enter values, or set them in the script." -ForegroundColor Red
        exit 1
    }
}

# Build Azure CLI command
$setEnvVarsArg = @()
foreach ($key in $envVars.Keys) {
    if (-not [string]::IsNullOrWhiteSpace($envVars[$key])) {
        $setEnvVarsArg += "$key=$($envVars[$key])"
    }
}

$azCommand = "az containerapp update -g $ResourceGroup -n $ContainerApp --set-env-vars $($setEnvVarsArg -join ' ')"

Write-Host "Deployment Command:" -ForegroundColor Cyan
Write-Host "---" -ForegroundColor Gray
Write-Host $azCommand -ForegroundColor Gray
Write-Host "---" -ForegroundColor Gray
Write-Host ""

if ($DryRun) {
    Write-Host "✓ DRY RUN: Command prepared but not executed." -ForegroundColor Green
    exit 0
}

Write-Host "Executing deployment..." -ForegroundColor Cyan
try {
    Invoke-Expression $azCommand
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✓ SUCCESS: Environment variables updated." -ForegroundColor Green
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "  1. Verify deployment: az containerapp show -g $ResourceGroup -n $ContainerApp"
        Write-Host "  2. Check logs: az containerapp logs show -g $ResourceGroup -n $ContainerApp"
        Write-Host "  3. Monitor: https://portal.azure.com"
    } else {
        Write-Host "✗ ERROR: Deployment failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "✗ ERROR: $($_)" -ForegroundColor Red
    exit 1
}
