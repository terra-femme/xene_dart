#!/bin/bash
# Azure Container Apps Deployment Script (Bash)
# Sets environment variables for xene_backend deployment
#
# Usage: ./deploy_azure_env.sh -g "xene-rg" -n "xene-backend" [-e production] [--dry-run] [--interactive]
#
# Prerequisites:
#   - Azure CLI installed and authenticated: az login
#   - Required role: Contributor or higher on the resource group
#
# Note: Secrets (API keys, tokens) should be fetched from Azure Key Vault or provided interactively

set -euo pipefail

# Parse command line arguments
RESOURCE_GROUP=""
CONTAINER_APP=""
ENVIRONMENT="production"
DRY_RUN=false
INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -n|--container-app)
            CONTAINER_APP="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 -g RESOURCE_GROUP -n CONTAINER_APP [-e ENVIRONMENT] [--dry-run] [--interactive]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$RESOURCE_GROUP" || -z "$CONTAINER_APP" ]]; then
    echo "Error: -g (resource group) and -n (container app) are required"
    exit 1
fi

echo "Azure Container Apps Environment Configuration"
echo "==============================================="
echo ""

# Environment variables (key=default_value format)
declare -A ENV_VARS=(
    # XENE DEPLOYMENT CONFIG
    [XENE_ENV]="$ENVIRONMENT"

    # YOUTUBE API CONFIG
    [YOUTUBE_REFRESH_BATCH_SIZE]="300"

    # CORS SECURITY - CRITICAL: set to your production domain
    [ALLOWED_ORIGINS]="https://xene.app,https://www.xene.app"

    # SUPABASE - from Supabase dashboard Settings → API
    [SUPABASE_URL]=""
    [SUPABASE_SERVICE_KEY]=""

    # OAUTH & API CREDENTIALS
    [SC_CLIENT_ID]=""
    [SC_CLIENT_SECRET]=""
    [TWITCH_CLIENT_ID]=""
    [TWITCH_CLIENT_SECRET]=""
    [IG_APP_ID]=""
    [IG_APP_SECRET]=""
    [IG_REDIRECT_URI]="https://xene-backend.azurecontainerapps.io/auth/instagram/callback"
    [BEATPORT_USERNAME]=""
    [BEATPORT_PASSWORD]=""

    # LLM & DISCOVERY
    [GEMINI_API_KEY]=""

    # TOKEN ENCRYPTION - CRITICAL: 32 hex characters
    [TOKEN_ENCRYPTION_KEY]=""

    # ADMIN ACCESS - CRITICAL: random secret for /admin/poll
    [ADMIN_SECRET]=""

    # FRONTEND INTEGRATION
    [FRONTEND_URL]="https://xene.app"

    # SCHEDULER CONFIG
    [PUBLICATION_STARTUP_POLL]="false"
)

echo "Configuration Summary:"
echo "  Resource Group:    $RESOURCE_GROUP"
echo "  Container App:     $CONTAINER_APP"
echo "  Environment:       $ENVIRONMENT"
echo "  Total Env Vars:    ${#ENV_VARS[@]}"
echo ""

# Check for empty required variables
required_vars=(SUPABASE_URL SUPABASE_SERVICE_KEY SC_CLIENT_ID SC_CLIENT_SECRET TOKEN_ENCRYPTION_KEY ADMIN_SECRET GEMINI_API_KEY)
missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${ENV_VARS[$var]}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "⚠️  Missing Required Variables:"
    for var in "${missing_vars[@]}"; do
        echo "   - $var"
    done
    echo ""

    if [[ "$INTERACTIVE" == "true" ]]; then
        echo "Enter values for missing variables (or press Enter to skip):"
        for var in "${missing_vars[@]}"; do
            read -p "  $var: " value
            if [[ -n "$value" ]]; then
                ENV_VARS[$var]="$value"
            fi
        done
    else
        echo "ERROR: Cannot proceed with missing required variables."
        echo "Run with --interactive flag to enter values, or set them in the script."
        exit 1
    fi
fi

# Build environment variables string for Azure CLI
env_vars_str=""
for key in "${!ENV_VARS[@]}"; do
    if [[ -n "${ENV_VARS[$key]}" ]]; then
        env_vars_str="$env_vars_str $key='${ENV_VARS[$key]}'"
    fi
done

az_command="az containerapp update -g $RESOURCE_GROUP -n $CONTAINER_APP --set-env-vars$env_vars_str"

echo "Deployment Command:"
echo "---"
echo "$az_command" | sed 's/--set-env-vars /--set-env-vars \\\n  /g'
echo "---"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "✓ DRY RUN: Command prepared but not executed."
    exit 0
fi

echo "Executing deployment..."
if eval "$az_command"; then
    echo ""
    echo "✓ SUCCESS: Environment variables updated."
    echo ""
    echo "Next Steps:"
    echo "  1. Verify deployment: az containerapp show -g $RESOURCE_GROUP -n $CONTAINER_APP"
    echo "  2. Check logs: az containerapp logs show -g $RESOURCE_GROUP -n $CONTAINER_APP"
    echo "  3. Monitor: https://portal.azure.com"
else
    echo "✗ ERROR: Deployment failed"
    exit 1
fi
