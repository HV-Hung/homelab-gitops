# homelab-gitops

A GitOps monorepo for managing a home Kubernetes cluster (k3s) using ArgoCD, Helm, and HashiCorp Vault.

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

## Bootstrap (First-Time Setup)

Run once against a fresh k3s cluster:

```bash
cd bootstrap
./bootstrap.sh
```

This script:
1. Creates all namespaces and storage classes
2. Installs ArgoCD via Helm
3. Applies `root.yaml` to kick off the GitOps loop

> **Note:** Before running, manually create the `vault-kms-creds` secret in the `vault` namespace with Azure service principal credentials for Vault auto-unseal.
>
> ```bash
> kubectl create secret generic vault-kms-creds -n vault \
>   --from-literal=AZURE_TENANT_ID=<tenant_id> \
>   --from-literal=AZURE_CLIENT_ID=<client_id> \
>   --from-literal=AZURE_CLIENT_SECRET=<client_secret>
> ```

## Directory Structure

```
.
├── apps/
│   ├── _chart/          # Library Helm chart (reusable templates)
│   └── <service>/       # One chart per service, depends on _chart
├── argocd-apps/
│   └── infra/           # ArgoCD Application manifests for infra layer
├── bootstrap/
│   ├── root.yaml        # The App of Apps entry point
│   ├── bootstrap.sh     # One-shot bootstrap script
│   └── core/            # ApplicationSets and AppProjects managed by ArgoCD
├── cluster/
│   ├── namespaces.yaml  # All cluster namespaces
│   └── storage-classes.yaml
└── infra/
    ├── argocd/          # ArgoCD Helm values
    ├── cloudflare/      # Cloudflare tunnel manifests
    ├── databases/       # PostgreSQL Helm values
    ├── env-base/        # Per-environment baseline Helm chart
    ├── ingress/         # ingress-nginx Helm values
    ├── monitoring/      # kube-prometheus-stack Helm values
    └── vault/           # Vault server + VSO Helm values and extra manifests
```

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

## Environments

| Env | Namespace | DB User | Ingress Host |
|---|---|---|---|
| dev | `dev` | `dev_user` | `dev-*.hungops.tech` |
| prod | `prod` | `prod_user` | `*.hungops.tech` |

## Security Notes

- **ArgoCD Projects**: The `infra` project has full cluster access; the `apps` project is restricted to `dev`/`prod` namespaces only with no cluster-scoped resources.
- **Secrets**: All runtime secrets are pulled from Vault via the Vault Secrets Operator. No secrets are stored in Git.
- **Vault TLS**: Vault's internal listener has TLS disabled (`tls_disable = 1`). External access is encrypted via the Nginx ingress + TLS termination. Internal cluster traffic to Vault is unencrypted — accepted risk for a home lab.
- **Vault auto-unseal**: Uses Azure Key Vault (BYOK). Vault can restart and unseal automatically without manual intervention.
