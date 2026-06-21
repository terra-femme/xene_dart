# Dashboard Deployment to Azure Container Apps

This guide walks you through deploying the Next.js admin dashboard to Azure Container Apps.

## Prerequisites

- Azure subscription with an existing resource group (`xene-rg`)
- Azure CLI installed (`az --version`)
- Docker installed (`docker --version`)
- GitHub Actions secrets configured (see below)

## Architecture

```
GitHub (main branch push)
    ↓
GitHub Actions Workflow
    ↓
Build Docker image
    ↓
Push to Azure Container Registry (ACR)
    ↓
Deploy to Azure Container Apps
    ↓
Dashboard live at: https://xene-dashboard.{region}.azurecontainerapps.io
```

## Step 1: Set Up Azure Container Registry (ACR)

If you don't already have an ACR, create one:

```bash
az acr create \
  --resource-group xene-rg \
  --name xeneacr \
  --sku Basic \
  --admin-enabled false
```

Verify it exists:

```bash
az acr list --resource-group xene-rg
```

## Step 2: Create Azure Container App for Dashboard

Create the container app environment (if it doesn't exist):

```bash
az containerapp env create \
  --name xene-env \
  --resource-group xene-rg \
  --location eastus
```

Create the dashboard container app:

```bash
az containerapp create \
  --name xene-dashboard \
  --resource-group xene-rg \
  --environment xene-env \
  --image xeneacr.azurecr.io/xene-dashboard:latest \
  --target-port 3000 \
  --ingress external \
  --query properties.configuration.ingress.fqdn
```

**Save the FQDN** (fully qualified domain name) — this is your dashboard URL.

## Step 3: Configure Environment Variables in Azure

Set the production environment variables in Azure:

```bash
# Supabase configuration
az containerapp secret set \
  --name xene-dashboard \
  --resource-group xene-rg \
  --secrets \
    supabase-url="your-supabase-url" \
    supabase-anon-key="your-supabase-anon-key" \
    supabase-service-key="your-supabase-service-key" \
    backend-url="https://xene-backend.azurecontainerapps.io" \
    admin-secret="your-admin-secret"

# Update container app with environment variables
az containerapp update \
  --name xene-dashboard \
  --resource-group xene-rg \
  --env-vars \
    "NEXT_PUBLIC_SUPABASE_URL=secretref:supabase-url" \
    "NEXT_PUBLIC_SUPABASE_ANON_KEY=secretref:supabase-anon-key" \
    "SUPABASE_SERVICE_ROLE_KEY=secretref:supabase-service-key" \
    "NEXT_PUBLIC_BACKEND_URL=secretref:backend-url" \
    "ADMIN_SECRET=secretref:admin-secret"
```

Replace the placeholder values with your actual Supabase and backend credentials.

## Step 4: Configure GitHub Actions Secrets

Add the following secrets to your GitHub repository:

Go to: **Settings → Secrets and variables → Actions**

Add:
- `AZURE_CLIENT_ID` — your Azure service principal client ID
- `AZURE_TENANT_ID` — your Azure tenant ID
- `AZURE_SUBSCRIPTION_ID` — your Azure subscription ID

(If you already have these from backend deployment, reuse them.)

## Step 5: Deploy via GitHub Actions

Push to `main` branch with changes to `packages/xene_dashboard/`:

```bash
git add packages/xene_dashboard/
git commit -m "feat(dashboard): add Azure Container Apps deployment"
git push origin feat/branch-name

# Then create a PR on GitHub and merge to main
```

GitHub Actions will automatically:
1. Build the Docker image
2. Push to ACR
3. Deploy to Azure Container Apps

Watch the deployment at: **GitHub → Actions → Deploy Dashboard to Azure Container Apps**

## Step 6: Verify Deployment

Check the container app status:

```bash
az containerapp show \
  --name xene-dashboard \
  --resource-group xene-rg \
  --query properties.provisioningState
```

Should return: `"Succeeded"`

View logs:

```bash
az containerapp logs show \
  --name xene-dashboard \
  --resource-group xene-rg \
  --follow
```

Access the dashboard at the FQDN you saved earlier:

```
https://xene-dashboard.{region}.azurecontainerapps.io
```

## Troubleshooting

### Container won't start
- Check logs: `az containerapp logs show --name xene-dashboard --resource-group xene-rg`
- Verify environment variables are set
- Ensure Supabase credentials are correct

### Image push fails
- Verify ACR credentials: `az acr login --name xeneacr`
- Check ACR storage quota: `az acr show --name xeneacr --query storageAccount`

### Deploy fails in GitHub Actions
- Verify AZURE_* secrets are correct
- Check Azure credentials have permission to update container apps

## Next Steps

1. **Custom domain**: Add a custom domain to the container app via Azure Portal
2. **Auto-scaling**: Configure CPU/memory scaling in the container app
3. **Monitoring**: Set up Azure Monitor alerts for uptime/errors
4. **CI/CD refinement**: Add tests to the workflow before deployment

## References

- [Azure Container Apps Docs](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Next.js Docker Guide](https://nextjs.org/docs/deployment/docker)
- [ACR Docs](https://learn.microsoft.com/en-us/azure/container-registry/)
