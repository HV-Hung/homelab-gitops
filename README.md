# homelab-gitops

A GitOps monorepo for managing a home Kubernetes cluster (k3s) using ArgoCD, Helm, HashiCorp Vault, and Terraform.

## Architecture

This repo follows the **App of Apps** pattern. A single root Application bootstraps ArgoCD, which then manages everything else declaratively.

```
bootstrap/root.yaml               ← Applied once manually to seed ArgoCD
│
└── bootstrap/core/               ← ArgoCD manages this folder
    ├── cluster-infra.yaml        → argocd-apps/infra/   (infrastructure Applications)
    ├── cluster-envs.yaml         → infra/env-base/       (per-env baseline: SA, VaultAuth, Secrets)
    ├── cluster-apps.yaml         → apps/*/               (matrix: app × environment)
    └── projects.yaml             → AppProject definitions
```

### Layer Breakdown

| Layer | Path | ArgoCD Project | Description |
|---|---|---|---|
| Cluster primitives | `cluster/` | n/a (kubectl) | Namespaces, StorageClasses |
| Infrastructure | `argocd-apps/infra/` + `infra/` | `infra` | ingress-nginx, Vault, PostgreSQL, monitoring, Cloudflare |
| Env baseline | `infra/env-base/` | `infra` | Per-namespace ServiceAccount, VaultAuth, VaultStaticSecret |
| Applications | `apps/<service>/` | `apps` | Service Helm charts consuming the library chart |
| Provisioning | `terraform/` | n/a (Terraform) | Zero-trust Azure identity + Vault configuration |

## Operations Runbook

### 1. Zero Trust Setup (Azure Identity)

Run this one-time step to create the Azure AD Application, Key Vault, and least-privilege Role Assignments needed for Vault's auto-unseal.

```bash
cd terraform/azure
terraform init
terraform apply

# Export outputs as K8s secret before starting cluster tools
kubectl create namespace vault
kubectl create secret generic vault-kms-creds -n vault \
  --from-literal=AZURE_TENANT_ID=$(terraform output -raw azure_tenant_id) \
  --from-literal=AZURE_CLIENT_ID=$(terraform output -raw azure_client_id) \
  --from-literal=AZURE_CLIENT_SECRET=$(terraform output -raw azure_client_secret)
```

### 2. Bootstrap (First-Time Setup)

Run once against a fresh k3s cluster (after step 1):

```bash
cd bootstrap
./bootstrap.sh
```

This script is idempotent. It will:
1. Create all namespaces and storage classes
2. Upgrade/Install ArgoCD via Helm
3. Apply `root.yaml` to kick off the GitOps loop

### 3. Vault Configuration (Post-Install)

Once the cluster is bootstrapped and Vault is unsealed (happens automatically via Azure KV):

```bash
# Authenticate
export VAULT_ADDR="http://vault.hungops.tech" 
export VAULT_TOKEN="<your-root-token>"

# Configure Auth Methods, Policies, and Roles per namespace
cd terraform/vault
terraform init
terraform apply

# Populate secrets manually (one-time manual data entry)
vault kv put secret/admin DB_PASSWORD="..."
vault kv put secret/dev DB_PASSWORD="..."
vault kv put secret/prod DB_PASSWORD="..."
vault kv put secret/cloudflare token="..."
```

### 4. Teardown (Full Cleanup)

If you need to nuke the cluster workloads and start fresh (k3s node remains active):

> **⚠️ WARNING:** This is destructive. Persistent volumes (Postgres DB, Vault data) will be deleted. Ensure secrets are backed up.

```bash
cd bootstrap
./teardown.sh
```

## Security & Access Control

- **ArgoCD Projects**: The `infra` project has full cluster access. `apps` project is restricted to `dev`/`prod` namespaces with no cluster-scoped resources.
- **Secrets Management**: All runtime secrets are pulled from Vault via Vault Secrets Operator (VSO). No secrets are stored in Git.
- **Vault Least Privilege**: Policies are isolated by namespace via Terraform. A compromised pod in `dev` cannot read secrets for `prod` or `cloudflared`.
- **Vault Auto-Unseal**: Uses Azure Key Vault (BYOK) configured via Terraform with strict `Key Vault Crypto User` permissions allowing only key wrap/unwrap operations.

## Adding a New Application

1. Create a new chart directory under `apps/<app-name>/`
2. Add a `Chart.yaml` that depends on `_chart`:
   ```yaml
   dependencies:
     - name: app
       version: 0.1.0
       repository: "file://../_chart"
   ```
3. Add `values.yaml`, `values-dev.yaml`, `values-prod.yaml`
4. Add a `templates/all.yaml` that calls the library templates
5. The `cluster-apps` ApplicationSet will automatically detect and deploy the new app
