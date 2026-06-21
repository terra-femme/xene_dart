# Azure Deploy Runbook — Dart Frog backend (ACR + Container Apps)

> **Draft commands. Nothing has been run** (Azure CLI is not installed yet). Verified flag
> syntax against Microsoft Learn docs. PowerShell (Windows) style — variables + backtick
> line-continuation. Replace every `<...>` placeholder before running.
>
> Env-var list is **grounded in code** — `grep Platform.environment` across `packages/xene_backend`.
> Target: **Azure Container Apps**, scale-to-zero, image pulled via system-assigned managed
> identity (no admin creds, no static registry password).

---

## 0. One-time prerequisites

```powershell
# Install + sign in (you don't have az yet)
winget install Microsoft.AzureCLI
# (open a fresh terminal so `az` is on PATH)
az login
az account set --subscription "<YOUR_SUBSCRIPTION_NAME_OR_ID>"

# Container Apps CLI extension + required resource providers
az extension add --name containerapp --upgrade
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ContainerRegistry
```

---

## 1. Variables (edit these)

```powershell
$RG        = "xene-rg"
$LOCATION  = "eastus"            # pick a region close to you / Supabase
$ACR       = "xeneacr$((Get-Random -Maximum 9999))"  # must be globally unique, lowercase alnum
$ENV       = "xene-env"
$APP       = "xene-backend"
$TAG       = "v1"               # bump per release; avoid :latest for traceability
$FRONTEND  = "https://app.xene.app"   # your real frontend origin for CORS
```

---

## 2. Resource group, registry, and remote image build

`az acr build` uploads the build context and builds **in the cloud** — no local Docker needed.
Run from the **repo root** (context `.`, Dockerfile under `packages/xene_backend`):

```powershell
az group create -n $RG -l $LOCATION

az acr create -n $ACR -g $RG --sku Basic

# Build + push in one step (honors the repo-root .dockerignore)
az acr build -r $ACR -t "xene-backend:$TAG" -f packages/xene_backend/Dockerfile .
```

---

## 3. Container Apps environment

```powershell
az containerapp env create -n $ENV -g $RG -l $LOCATION
```

---

## 4. Create the app (private image via system-assigned managed identity)

`--registry-identity system` enables the system identity AND auto-creates the `AcrPull` role
assignment on the registry. Scale-to-zero (`--min-replicas 0`) is safe because external HTTP
ingress provides a wake-up path.

```powershell
az containerapp create -n $APP -g $RG --environment $ENV `
  --image "$ACR.azurecr.io/xene-backend:$TAG" `
  --registry-server "$ACR.azurecr.io" --registry-identity system `
  --target-port 8080 --ingress external `
  --min-replicas 0 --max-replicas 3 `
  --cpu 0.5 --memory 1.0Gi
```

> If the first revision fails to pull (identity/role race on older CLI), use the bulletproof
> fallback: create with a public image (`mcr.microsoft.com/k8se/quickstart:latest`), then
> `az containerapp registry set -n $APP -g $RG --identity system --server "$ACR.azurecr.io"`,
> then `az containerapp update -n $APP -g $RG --image "$ACR.azurecr.io/xene-backend:$TAG"`.

---

## 5. Secrets (stored encrypted as Container App secrets)

Secret **names** must be lowercase-alphanumeric + `-`. Pull the values from your local `.env`
into the shell first (so they don't sit in this file or your history), then:

```powershell
# Load values into the session from your .env however you prefer, e.g. set them manually:
#   $env:SUPABASE_SERVICE_KEY = "..."   etc.

az containerapp secret set -n $APP -g $RG --secrets `
  supabase-service-key=$env:SUPABASE_SERVICE_KEY `
  token-encryption-key=$env:TOKEN_ENCRYPTION_KEY `
  admin-secret=$env:ADMIN_SECRET `
  sc-client-id=$env:SC_CLIENT_ID `
  sc-client-secret=$env:SC_CLIENT_SECRET `
  twitch-client-id=$env:TWITCH_CLIENT_ID `
  twitch-client-secret=$env:TWITCH_CLIENT_SECRET `
  youtube-api-key=$env:YOUTUBE_API_KEY `
  beatport-username=$env:BEATPORT_USERNAME `
  beatport-password=$env:BEATPORT_PASSWORD `
  discogs-consumer-key=$env:DISCOGS_CONSUMER_KEY `
  discogs-consumer-secret=$env:DISCOGS_CONSUMER_SECRET `
  gemini-api-key=$env:GEMINI_API_KEY `
  openrouter-api-key=$env:OPENROUTER_API_KEY `
  nvidia-api-key=$env:NVIDIA_API_KEY
```

> Only set the integrations you actually use — the backend tolerates missing keys at boot
> (verified: the image boots and serves with **no** env set; integrations are lazy). The four
> that matter most for core function are `supabase-*`, `token-encryption-key`, `admin-secret`.

---

## 6. Environment variables (non-secret config + `secretref:` for secrets)

```powershell
az containerapp update -n $APP -g $RG --set-env-vars `
  XENE_ENV=production `
  "ALLOWED_ORIGINS=$FRONTEND" `
  TRUSTED_PROXY_HOPS=1 `
  SUPABASE_URL=$env:SUPABASE_URL `
  NVIDIA_MODEL=$env:NVIDIA_MODEL `
  "SUPABASE_SERVICE_KEY=secretref:supabase-service-key" `
  "TOKEN_ENCRYPTION_KEY=secretref:token-encryption-key" `
  "ADMIN_SECRET=secretref:admin-secret" `
  "SC_CLIENT_ID=secretref:sc-client-id" `
  "SC_CLIENT_SECRET=secretref:sc-client-secret" `
  "TWITCH_CLIENT_ID=secretref:twitch-client-id" `
  "TWITCH_CLIENT_SECRET=secretref:twitch-client-secret" `
  "YOUTUBE_API_KEY=secretref:youtube-api-key" `
  "BEATPORT_USERNAME=secretref:beatport-username" `
  "BEATPORT_PASSWORD=secretref:beatport-password" `
  "DISCOGS_CONSUMER_KEY=secretref:discogs-consumer-key" `
  "DISCOGS_CONSUMER_SECRET=secretref:discogs-consumer-secret" `
  "GEMINI_API_KEY=secretref:gemini-api-key" `
  "OPENROUTER_API_KEY=secretref:openrouter-api-key" `
  "NVIDIA_API_KEY=secretref:nvidia-api-key"
```

**Why these three config vars matter (from the code):**
- `XENE_ENV=production` → `_middleware.dart` makes CORS **fail closed**.
- `ALLOWED_ORIGINS` → the only origins CORS will echo (no `*` in prod).
- `TRUSTED_PROXY_HOPS=1` → `rate_limiter.dart` keys limiters on the real client IP behind
  the single Azure ingress proxy.

**Optional tuning flags** (defaults exist — set only if needed): `PRESS_SCOUT_BATCH_SIZE`,
`PRESS_SCOUT_ON_SAVE` / `XENE_PRESS_SCOUT_ON_SAVE`, `LLM_ENRICH_ON_SAVE` /
`XENE_LLM_ENRICH_ON_SAVE`, `PUBLICATION_STARTUP_POLL`, `YOUTUBE_REFRESH_BATCH_SIZE` /
`XENE_YOUTUBE_REFRESH_BATCH_SIZE`. `GOOGLE_API_KEY` is an alternative to `GEMINI_API_KEY`.

---

## 7. Wire the backend's own public URL (chicken-and-egg)

The backend reads `BACKEND_URL` + `SC_REDIRECT_URI` (SoundCloud OAuth callback). They need the
public FQDN, which only exists after the app is created:

```powershell
$FQDN = az containerapp show -n $APP -g $RG --query properties.configuration.ingress.fqdn -o tsv
az containerapp update -n $APP -g $RG --set-env-vars `
  "BACKEND_URL=https://$FQDN" `
  "SC_REDIRECT_URI=https://$FQDN/auth/soundcloud/callback"
```

> **Preferred:** put your own domain `api.xene.app` in front (step 9) and set
> `BACKEND_URL=https://api.xene.app` so a provider switch is a DNS repoint, not a re-deploy.
> If you do that, also register `https://api.xene.app/auth/soundcloud/callback` in the
> SoundCloud app settings.

---

## 8. Verify

```powershell
# Expect HTTP 401 — proves the server is up, routing, and auth middleware is live
curl.exe -s -o NUL -w "%{http_code}`n" "https://$FQDN/monitor"

# Logs (first revision)
az containerapp logs show -n $APP -g $RG --tail 50
```

---

## 9. Post-deploy follow-ups (each is its own task)

1. **Custom domain + managed cert** — `az containerapp hostname add` + `... bind` for
   `api.xene.app` (free managed certificate).
2. **Frontend dart-define** — build the app with
   `--dart-define=BACKEND_URL=https://api.xene.app` (default is still `http://localhost:8080`).
3. **SoundCloud app** — add the production redirect URI.
4. **Supabase Network Restrictions** — restrict the service key to the app's egress IP.
   ⚠️ *Caveat:* a Consumption Container Apps environment does **not** guarantee a single stable
   outbound IP. For a fixed egress IP you need a workload-profile/VNet environment + NAT
   gateway. Verify the real egress IP first (e.g. add a temporary route that echoes
   `api.ipify.org`) before locking Supabase, or defer this until the VNet decision.
5. **Budget guard** — `az consumption budget` / portal $5 alert.

---

## 10. Hardening (Tier 2) — move secrets to Azure Key Vault

Keeps secrets out of the Container App config entirely; rotation happens in Key Vault.

```powershell
$KV = "xene-kv$((Get-Random -Maximum 9999))"
az keyvault create -n $KV -g $RG -l $LOCATION

# Store a secret
az keyvault secret set --vault-name $KV --name supabase-service-key --value $env:SUPABASE_SERVICE_KEY

# Grant the app's system identity read access
$PRINCIPAL = az containerapp show -n $APP -g $RG --query identity.principalId -o tsv
az keyvault set-policy -n $KV --object-id $PRINCIPAL --secret-permissions get list
# (or RBAC: az role assignment create --assignee $PRINCIPAL --role "Key Vault Secrets User" --scope <kv-id>)

# Reference the KV secret from the Container App (identityref:system)
$KVURI = az keyvault secret show --vault-name $KV --name supabase-service-key --query id -o tsv
az containerapp secret set -n $APP -g $RG `
  --secrets "supabase-service-key=keyvaultref:$KVURI,identityref:system"
```

The `secretref:supabase-service-key` env mapping from step 6 stays the same — only the secret's
*source* changes from inline value to Key Vault reference. **No backend code change** (it always
reads `Platform.environment`).

---

## Env-var reference (grounded in `packages/xene_backend`)

| Var | Where read | Tier |
|---|---|---|
| `PORT` | server (auto-set by platform) | platform |
| `SUPABASE_URL` | `database.dart` | core (env) |
| `SUPABASE_SERVICE_KEY` | `database.dart` | core (**secret**) |
| `TOKEN_ENCRYPTION_KEY` | `token_store.dart` | core (**secret**) |
| `ADMIN_SECRET` | `admin/poll.dart` | core (**secret**) |
| `XENE_ENV` | `_middleware.dart` | config (env) |
| `ALLOWED_ORIGINS` | `_middleware.dart` | config (env) |
| `TRUSTED_PROXY_HOPS` | `rate_limiter.dart` | config (env) |
| `BACKEND_URL` | `auth/soundcloud/callback.dart` | config (env, post-FQDN) |
| `SC_CLIENT_ID` / `SC_CLIENT_SECRET` / `SC_REDIRECT_URI` | `soundcloud/*`, `analysis_service.dart` | integration |
| `TWITCH_CLIENT_ID` / `TWITCH_CLIENT_SECRET` | `twitch_service.dart` | integration |
| `YOUTUBE_API_KEY` | `youtube_service.dart` | integration |
| `BEATPORT_USERNAME` / `BEATPORT_PASSWORD` | `beatport_service.dart` | integration |
| `DISCOGS_CONSUMER_KEY` / `DISCOGS_CONSUMER_SECRET` | `discogs_service.dart` | integration |
| `GEMINI_API_KEY` / `GOOGLE_API_KEY` | `gemini_key_rotator.dart` | integration |
| `OPENROUTER_API_KEY` | `discovery_service.dart`, `press_scout_service.dart` | integration |
| `NVIDIA_API_KEY` / `NVIDIA_MODEL` | `discovery_service.dart` | integration |
| `PRESS_SCOUT_BATCH_SIZE`, `*_ON_SAVE`, `PUBLICATION_STARTUP_POLL`, `YOUTUBE_REFRESH_BATCH_SIZE` | various | optional tuning |

---

## 11. Custom domain `api.xene.app` + free managed TLS cert

Container Apps issues a **free, auto-renewing** managed certificate once the domain is publicly
reachable and DNS is correct. `api.xene.app` is a **subdomain → CNAME** flow.

```powershell
# 1. Generated app FQDN (the CNAME target) and the domain ownership code
$FQDN   = az containerapp show -n $APP -g $RG --query properties.configuration.ingress.fqdn -o tsv
$VERIFY = az containerapp show -n $APP -g $RG --query properties.customDomainVerificationId -o tsv
$FQDN; $VERIFY   # print both
```

**2. At your DNS provider, add two records** (replace values from above):

| Type  | Host          | Value                          |
|-------|---------------|--------------------------------|
| CNAME | `api`         | `$FQDN` (the app's generated domain) |
| TXT   | `asuid.api`   | `$VERIFY` (the verification code)    |

> ⚠️ The CNAME must map **directly** to the app domain — not through an intermediate proxy
> (Cloudflare orange-cloud, a Traffic Manager, etc.), or cert issuance/renewal fails. If your
> apex `xene.app` has a CAA record, add `0 issue digicert.com` or DigiCert can't issue.

```powershell
# 3. After DNS propagates: add the hostname, then bind (issues the managed cert)
az containerapp hostname add  -n $APP -g $RG --hostname api.xene.app
az containerapp hostname bind -n $APP -g $RG --hostname api.xene.app `
  --environment $ENV --validation-method CNAME
# Cert issuance can take several minutes. Verify:
az containerapp hostname list -n $APP -g $RG -o table
```

Then point the backend's self-URL + the app at the stable domain:
```powershell
az containerapp update -n $APP -g $RG --set-env-vars `
  "BACKEND_URL=https://api.xene.app" `
  "SC_REDIRECT_URI=https://api.xene.app/auth/soundcloud/callback"
# Frontend release build:
#   flutter build ... --dart-define=BACKEND_URL=https://api.xene.app
# SoundCloud app settings: register https://api.xene.app/auth/soundcloud/callback
```

---

## 12. GitHub Actions — auto-deploy on merge to `main` (OIDC, no stored secret)

Builds the image **in ACR** and rolls the Container App on every push to `main` that touches the
backend. Uses **OpenID Connect federated credentials** — short-lived tokens, no service-principal
password sitting in GitHub secrets (matches the "workload identity federation" goal in the
06-19 changelog).

### 12a. One-time: Entra app + federated credential + role

```powershell
# App registration + service principal
$APPID = az ad app create --display-name "xene-github-deploy" --query appId -o tsv
az ad sp create --id $APPID

# Federated credential trusting pushes to main of THIS repo.
# PowerShell quoting for inline JSON is painful — write a file and pass @file.
@'
{
  "name": "xene-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:terra-femme/xene_dart:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}
'@ | Out-File -Encoding utf8 fedcred.json
az ad app federated-credential create --id $APPID --parameters '@fedcred.json'
Remove-Item fedcred.json

# Grant it Contributor on the resource group (tighten to AcrPush + Container Apps roles later)
$SUBID = az account show --query id -o tsv
az role assignment create --assignee $APPID --role Contributor `
  --scope "/subscriptions/$SUBID/resourceGroups/$RG"

# Push the three non-secret IDs to GitHub (no password — OIDC)
$TENANT = az account show --query tenantId -o tsv
gh secret set AZURE_CLIENT_ID       --body $APPID
gh secret set AZURE_TENANT_ID       --body $TENANT
gh secret set AZURE_SUBSCRIPTION_ID --body $SUBID
```

### 12b. Workflow file — `.github/workflows/deploy-backend.yml`

```yaml
name: Deploy backend to Azure Container Apps

on:
  push:
    branches: [main]
    paths:
      - 'packages/xene_backend/**'
      - 'packages/xene_domain/**'
      - '.dockerignore'
      - '.github/workflows/deploy-backend.yml'
  workflow_dispatch:        # manual run button

permissions:
  id-token: write           # required for OIDC azure/login
  contents: read

env:
  ACR: <YOUR_ACR_NAME>      # e.g. xeneacr1234 (no .azurecr.io)
  APP: xene-backend
  RG:  xene-rg

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id:       ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Build image in ACR (commit-SHA tag, not :latest)
        run: |
          az acr build -r ${{ env.ACR }} \
            -t xene-backend:${{ github.sha }} \
            -f packages/xene_backend/Dockerfile .

      - name: Roll the Container App to the new image
        run: |
          az containerapp update -n ${{ env.APP }} -g ${{ env.RG }} \
            --image ${{ env.ACR }}.azurecr.io/xene-backend:${{ github.sha }}
```

**Notes**
- Tags images by `github.sha` (per Microsoft's image-tag guidance) — every deploy is traceable
  and rollback is just re-pointing `--image` at an older SHA.
- `az acr build` runs the build **in Azure**, so the GitHub runner needs no Docker layer caching
  or `docker login`.
- **Do not add this workflow until** the Azure resources (§2–4) and §12a federated credential +
  repo secrets exist — otherwise the first push fails at `azure/login`. When you do add it, ship
  it via a **feature branch → PR** (per the repo's GitHub protocol), not a direct push to `main`.
- The existing security workflows (CodeQL/Semgrep/pip-audit) still run on PRs independently; this
  deploy job is additive and only runs post-merge on `main`.

---

# Dashboard Deployment — Next.js Admin App

> **Status:** Infrastructure complete. GitHub Actions workflow merged to `main`. ACR image building.
> Waiting for: manual Container App creation in Azure + environment variable configuration.
>
> **What was done:** Created Supabase auth clients, Dockerfile (multi-stage), `.env.example`,
> GitHub Actions workflow, deployment guide, and automated PowerShell setup script.
>
> **What's left:** Run the Azure setup (4 commands or 1 PowerShell script) to create the
> Container App and wire environment variables. Then dashboard auto-deploys on every push to main
> that touches `packages/xene_dashboard/`.

---

## Dashboard Architecture

Same Container Apps environment as the backend, but separate Container App:

```
GitHub main → GitHub Actions workflow
  ↓ (auto-triggered on push to packages/xene_dashboard/)
Build Docker image (multi-stage Next.js)
  ↓
Push to Azure Container Registry (ACR: xeneacr7244)
  ↓
Update Container App (xene-dashboard)
  ↓
Dashboard live at: https://xene-dashboard.{region}.azurecontainerapps.io
  (or custom domain later)
```

---

## Files Created

| File | Purpose |
|------|---------|
| `packages/xene_dashboard/lib/supabase/client.ts` | Browser auth client (OTP login) |
| `packages/xene_dashboard/lib/supabase/server.ts` | Server auth + admin client (service role) |
| `packages/xene_dashboard/.env.example` | Production config template (secrets + URLs) |
| `packages/xene_dashboard/Dockerfile` | Multi-stage build (non-root user, healthcheck, dumb-init) |
| `.github/workflows/deploy-dashboard-azure.yml` | CI/CD workflow (OIDC, auto-deploy on push to main) |
| `docs/DASHBOARD_DEPLOYMENT_AZURE.md` | Comprehensive deployment guide |
| `docs/education/Dockerfile.educational.md` | Line-by-line Dockerfile breakdown |
| `setup-dashboard-azure.ps1` | PowerShell automation (reads .env.local, runs all 4 Azure commands) |

---

## Setup: Two Options

### Option A: Manual Commands (Transparent, 5 min)

Replace `"your-url"`, `"your-key"` placeholders with actual values from `packages/xene_dashboard/.env.local`:

```powershell
# 1. Create Container App environment (if it doesn't exist)
az containerapp env create --name xene-env --resource-group xene-rg --location eastus

# 2. Create the dashboard Container App
az containerapp create --name xene-dashboard --resource-group xene-rg --environment xene-env `
  --image xeneacr7244.azurecr.io/xene-dashboard:latest --target-port 3000 --ingress external

# 3. Add secrets to Azure (encrypted at rest in Container App)
az containerapp secret set --name xene-dashboard --resource-group xene-rg --secrets `
  supabase-url="your-supabase-url" `
  supabase-anon-key="your-anon-key" `
  supabase-service-key="your-service-key" `
  backend-url="https://xene-backend.azurecontainerapps.io" `
  admin-secret="your-admin-secret"

# 4. Wire environment variables (non-secret + secretrefs)
az containerapp update --name xene-dashboard --resource-group xene-rg --env-vars `
  "NEXT_PUBLIC_SUPABASE_URL=secretref:supabase-url" `
  "NEXT_PUBLIC_SUPABASE_ANON_KEY=secretref:supabase-anon-key" `
  "SUPABASE_SERVICE_ROLE_KEY=secretref:supabase-service-key" `
  "NEXT_PUBLIC_BACKEND_URL=secretref:backend-url" `
  "ADMIN_SECRET=secretref:admin-secret"
```

### Option B: Automated PowerShell Script (1 min, no typing)

The script reads `.env.local` automatically and runs all 4 commands:

```powershell
cd C:\Users\aznkr\documents\fun_apps\xene\xene_dart\.claude\worktrees\azure-deploy
.\setup-dashboard-azure.ps1
```

**What the script does:**
1. Finds `packages/xene_dashboard/.env.local`
2. Extracts `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, etc.
3. Runs all 4 Azure commands with your actual values
4. Prints your dashboard URL at the end

---

## Why Manual Secret Injection?

**Question:** "Why can't the dashboard just read secrets from `.env.local`?"

**Answer:** Security

- `.env.local` lives on your machine (local, never committed to git ✓)
- Azure Container Apps runs in the cloud (can't access your local filesystem)
- Secrets must be stored in Azure's encrypted secret vault (Container App secrets)
- The container reads them at runtime from Azure, not from a file
- If secrets were in the Docker image, they'd be exposed in ACR and image history ✗

**Container App secrets are encrypted at rest** (same as backend), so this is secure.

---

## What Happens After Setup

1. **Dashboard created** → accessible at the FQDN Azure generates
2. **GitHub Actions watches** → any push to `packages/xene_dashboard/` on `main` triggers:
   - Docker build (multi-stage: build → runtime)
   - Image push to ACR (xeneacr7244.azurecr.io)
   - Container App auto-updated with new image
3. **Admin-only gating** → dashboard enforces `role='admin'` via Supabase RLS check
4. **No dev dropdowns** — the dashboard is production-clean (dev UI is only on the Flutter app)

---

## Security Notes

| Concern | Status |
|---------|--------|
| Admin-only access | ✅ Enforced in `dashboard/layout.tsx:56` — redirects non-admins |
| Secret storage | ✅ Container App secrets (encrypted at rest) |
| Container user | ✅ Runs as non-root `nextjs` (UID 1001) |
| Signal handling | ✅ dumb-init ensures graceful shutdown |
| GitHub Actions | ✅ Uses OIDC federation (no long-lived secrets) |

---

## Verification (After Setup)

```powershell
# Check Container App is running
az containerapp show --name xene-dashboard --resource-group xene-rg --query "properties.provisioningState"
# Expected: "Succeeded"

# Get your dashboard URL
az containerapp show --name xene-dashboard --resource-group xene-rg `
  --query "properties.configuration.ingress.fqdn" -o tsv

# View logs (first 50 lines)
az containerapp logs show --name xene-dashboard --resource-group xene-rg --tail 50

# Test the auth flow
# Open the URL in a browser → enter your admin email → should receive OTP magic link
```

---

## Post-Deploy Follow-ups

1. **Custom domain** (optional, but recommended):
   ```powershell
   # Use the same pattern as the backend (§11)
   # e.g., dashboard.xene.app → managed TLS cert
   $FQDN = az containerapp show -n xene-dashboard -g xene-rg --query properties.configuration.ingress.fqdn -o tsv
   $VERIFY = az containerapp show -n xene-dashboard -g xene-rg --query properties.customDomainVerificationId -o tsv
   # Then add CNAME + TXT records at your DNS provider
   ```

2. **Update frontend build**:
   ```bash
   # Flutter app needs to know the dashboard URL (for admin links, if any)
   flutter build ... --dart-define=DASHBOARD_URL=https://dashboard.xene.app
   ```

3. **Monitor deployments**:
   - GitHub Actions: https://github.com/terra-femme/xene_dart/actions
   - Container App logs: `az containerapp logs show ...`

---

## Troubleshooting

| Issue | Debug Command | Fix |
|-------|---------------|-----|
| Container won't start | `az containerapp logs show --name xene-dashboard ...` | Check env vars (likely Supabase URL missing) |
| "Image not found" in logs | `az acr repository list -n xeneacr7244` | Verify ACR image was pushed (check GitHub Actions run) |
| Admin auth fails | Log in to Supabase → check `profiles` table has your user with `role='admin'` | Add yourself as admin in Supabase |
| Deployment workflow didn't trigger | Check `.github/workflows/deploy-dashboard-azure.yml` path triggers | Make sure you pushed to `main` and edited `packages/xene_dashboard/` |

---

## Dockerfile Design (Why It's Built This Way)

**Multi-stage build:**
- **Stage 1 (Builder):** `npm ci` + `npm run build` → compiles Next.js (~500MB)
- **Stage 2 (Runtime):** Copy only `.next/`, `node_modules/`, `public/` → final image ~200MB (60% smaller)
- **Why:** Faster deploys, less storage, faster container startup

**Non-root user:**
- Runs as `nextjs` (UID 1001), not `root`
- Limits blast radius if container is compromised

**Dumb-init:**
- Ensures Node.js receives SIGTERM/SIGKILL correctly (important in Kubernetes)
- Enables graceful shutdown on Container App updates

**Healthcheck:**
- Every 30s, HTTP GET to `/` → Container App auto-restarts if unhealthy
- `start-period=40s` → waits 40s before first check (gives app time to boot)

See `docs/education/Dockerfile.educational.md` for line-by-line explanation.

