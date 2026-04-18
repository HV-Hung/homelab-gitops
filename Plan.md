# Homelab GitOps Implementation Plan

## Overview

Single k3s node cluster managed entirely through a GitOps repo using ArgoCD.
One repo, one source of truth for all cluster state.

---

## Repository Structure

```
homelab-gitops/
├── bootstrap/
│   └── bootstrap.sh              # One-time manual cluster bootstrap
│
├── argocd-apps/                  # App of Apps — ArgoCD Application manifests
│   ├── root.yaml                 # The only manifest applied manually (ever)
│   ├── infra/
│   │   ├── ingress.yaml
│   │   ├── cloudflare.yaml
│   │   ├── vault-server.yaml
│   │   ├── vault-operator.yaml
│   │   ├── vault-operator-config.yaml
│   │   ├── databases.yaml
│   │   └── monitoring.yaml
│   └── apps/
│       ├── dev.yaml
│       └── prod.yaml
│
├── infra/                        # Upstream Helm charts via values.yaml
│   ├── argocd/
│   │   └── values.yaml
│   ├── ingress/
│   │   └── values.yaml
│   ├── cloudflare/
│   │   ├── values.yaml           # cloudflared deployment config
│   │   └── tunnel-secret.yaml    # SOPS-encrypted tunnel token (never plain text)
│   ├── vault/                      # Vault and Vault Secrets Operator
│   │   ├── server/
│   │   │   ├── values.yaml
│   │   │   └── ingress.yaml
│   │   ├── operator/
│   │   │   ├── values.yaml
│   │   │   └── crds/
│   │   │       └── operator-config.yaml
│   │   └── README.md             # Manual init and auto-unseal steps
│   ├── databases/
│   │   ├── postgresql/
│   │   │   └── values.yaml
│   │   ├── redis/
│   │   │   └── values.yaml
│   │   └── rabbitmq/
│   │       └── values.yaml
│   └── monitoring/
│       ├── kube-prometheus-stack/
│       │   └── values.yaml
│       ├── loki/
│       │   └── values.yaml
│       ├── tempo/
│       │   └── values.yaml
│       └── alloy/
│           └── values.yaml
│
├── apps/
│   ├── _chart/                   # Single generic Helm chart for all Go apps
│   │   ├── Chart.yaml
│   │   ├── templates/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── ingress.yaml
│   │   │   ├── hpa.yaml          # Enabled via values flag
│   │   │   ├── cronjob.yaml      # Enabled via values flag
│   │   │   └── configmap.yaml
│   │   └── values.yaml           # Safe defaults
│   ├── dev/
│   │   ├── api-service/
│   │   │   └── values.yaml
│   │   └── worker-service/
│   │       └── values.yaml
│   └── prod/
│       ├── api-service/
│       │   └── values.yaml
│       └── worker-service/
│           └── values.yaml
│
└── cluster/                      # Raw manifests — trivial resources only
    ├── namespaces.yaml
    └── storage-classes.yaml
```

---

## Namespaces

```yaml
# cluster/namespaces.yaml
- dev
- prod
- databases
- monitoring
- argocd
- ingress
- cloudflare
- vault
```

---

## Phase 1 — Bootstrap (Manual, Once)

> Goal: Get base cluster resources and ArgoCD running.

### Steps

1. **Run the bootstrap script**
   ```bash
   # bootstrap/bootstrap.sh
   ./bootstrap/bootstrap.sh
   ```

   This script applies manifests in `cluster/` (namespaces, storage classes) and installs ArgoCD via Helm.

2. **Apply the root App of Apps**
   ```bash
   kubectl apply -f argocd-apps/root.yaml
   ```

3. **Apply the root App of Apps**
   ```bash
   kubectl apply -f argocd-apps/root.yaml
   ```

   After this, ArgoCD manages everything. No more manual installs.

---

## Phase 2 — Infrastructure (ArgoCD syncs, you approve)

> Sync policy: **manual** for all infra. You decide when to apply changes.

### Deploy order using sync waves

| Wave | Component | Namespace |
|------|-----------|-----------|
| -5 | vault server | vault |
| -4 | vault secrets operator | vault |
| -3 | vault CRDs, ingress-nginx, cloudflared | vault, ingress, cloudflare |
| -2 | postgresql, redis, rabbitmq | databases |
| -1 | kube-prometheus-stack, loki, tempo, alloy | monitoring |
| 0 | ArgoCD self-management | argocd |

> **Why Vault first?** Vault Secrets Operator (VSO) needs Vault running to connect on startup. Everything else that needs secrets (DBs, apps) comes after VSO is ready.

Annotate each Application manifest:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
```

### Helm chart sources

| Component | Chart | Repo |
|-----------|-------|------|
| ingress-nginx | ingress-nginx/ingress-nginx | https://kubernetes.github.io/ingress-nginx |
| cloudflared | cloudflare/cloudflare-tunnel-ingress-controller | https://cloudflare.github.io/helm-charts |
| vault | hashicorp/vault | https://helm.releases.hashicorp.com |
| vault-secrets-operator | hashicorp/vault-secrets-operator | https://helm.releases.hashicorp.com |
| postgresql | bitnami/postgresql | https://charts.bitnami.com/bitnami |
| redis | bitnami/redis | https://charts.bitnami.com/bitnami |
| rabbitmq | bitnami/rabbitmq | https://charts.bitnami.com/bitnami |
| kube-prometheus-stack | prometheus-community/kube-prometheus-stack | https://prometheus-community.github.io/helm-charts |
| loki | grafana/loki | https://grafana.github.io/helm-charts |
| tempo | grafana/tempo | https://grafana.github.io/helm-charts |
| alloy | grafana/alloy | https://grafana.github.io/helm-charts |
| argocd | argo/argo-cd | https://argoproj.github.io/argo-helm |

---

## Phase 2b — Vault + Vault Secrets Operator (VSO)

> This is the most critical infra dependency. Everything that needs secrets depends on this being healthy.

### Vault Setup and Azure Auto-Unseal

Vault is deployed using the official HashiCorp Helm chart. We are using **Azure Key Vault** to automatically unseal Vault on startup. This prevents the cluster from locking up during a node restart.

Due to the nature of Vault bootstrapping, there are manual steps required upon the very first installation. **Please refer to `infra/vault/README.md` for the exact manual bootstrap instructions**, which include:
- Creating the Azure Key Vault and Service Principal (or Workload Identity).
- The initial `vault operator init -key-shares=1 -key-threshold=1`.
- Applying Vault policies, roles, and Kubernetes auth configurations.

### Vault Secrets Operator Setup

HashiCorp Vault Secrets Operator (VSO) syncs secrets natively from Vault to Kubernetes. You deploy it via Helm and then define the connection inside the cluster.

```yaml
# infra/vault/operator/operator-config.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
  namespace: vault
spec:
  address: http://vault.vault.svc.cluster.local:8200

---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuthGlobal
metadata:
  name: default
  namespace: vault
  allowedNamespaces:
    - default
  defaultAuthMethod: kubernetes
  kubernetes:
    audiences:
    - vault
    mount: kubernetes
    tokenExpirationSeconds: 600
```

### How apps consume secrets

Services declare a `VaultStaticSecret` or `VaultDynamicSecret` manifest. VSO handles syncing this to a local Kubernetes `Secret`.

```yaml
# apps/prod/api-service/vault-secret.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: api-service-secrets
  namespace: prod
spec:
  type: kv-v2
  mount: secret
  path: prod/api-service
  destination:
    name: api-service-secrets    # Name of the k8s Secret VSO creates
    create: true
  refreshAfter: 5m
```

The app simply reads `api-service-secrets` via env vars or mounts. No Vault SDK needed in the app code.

### Vault secret path convention

```
secret/
├── prod/
│   ├── api-service/       # DB creds, API keys, etc.
│   └── worker-service/
├── dev/
│   ├── api-service/
│   └── worker-service/
└── infra/
    ├── databases/          # DB root passwords
    ├── monitoring/         # Grafana admin, alertmanager webhook
    └── cloudflare/         # Tunnel token
```

---

## Phase 2c — Cloudflare Tunnel

> Exposes your cluster to the internet without opening ports on your router. Cloudflare proxies all traffic through the tunnel to ingress-nginx.

### How it fits in the stack

```
Internet → Cloudflare Edge → cloudflared (tunnel) → ingress-nginx → services
```

`cloudflared` runs as a Deployment in the `cloudflare` namespace. It dials outbound to Cloudflare — no inbound ports needed.

### Setup steps

1. **Create tunnel in Cloudflare dashboard** (one-time, manual)
   - Go to Zero Trust → Networks → Tunnels → Create tunnel
   - Copy the tunnel token

2. **Store token in Vault:**
   ```bash
   vault kv put secret/infra/cloudflare tunnel_token="<your-token>"
   ```

3. **Create VaultStaticSecret for the tunnel token:**
   ```yaml
   # infra/cloudflare/tunnel-secret.yaml
   apiVersion: secrets.hashicorp.com/v1beta1
   kind: VaultStaticSecret
   metadata:
     name: cloudflare-tunnel-token
     namespace: cloudflare
   spec:
     type: kv-v2
     mount: secret
     path: infra/cloudflare
     destination:
       name: cloudflare-tunnel-credentials
       create: true
     refreshAfter: 1h
   ```

4. **Helm values for cloudflared:**
   ```yaml
   # infra/cloudflare/values.yaml
   cloudflare:
     tunnelName: "homelab"
     tunnelId: "<your-tunnel-id>"
     secretName: "cloudflare-tunnel-credentials"
     ingress:
       - hostname: "*.yourdomain.com"
         service: "http://ingress-nginx-controller.ingress.svc.cluster.local:80"
   ```



> Build the generic chart that all Go apps share.

### Feature flags in `apps/_chart/values.yaml`

```yaml
# Defaults — every flag opt-in
replicaCount: 1
image:
  repository: ""
  tag: "latest"

ingress:
  enabled: true
  host: ""

hpa:
  enabled: false
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80

cronjob:
  enabled: false
  schedule: ""

configmap:
  enabled: false
  data: {}

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

### Per-service values example

```yaml
# apps/prod/api-service/values.yaml
image:
  repository: your-registry/api-service
  tag: "1.4.2"

ingress:
  enabled: true
  host: api.yourdomain.com

hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 8

resources:
  requests:
    cpu: "200m"
    memory: "256Mi"
```

---

## Phase 4 — ArgoCD Application Manifests

### App of Apps root

```yaml
# argocd-apps/root.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/HV-Hung/homelab-gitops
    targetRevision: main
    path: argocd-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Infra Application example

```yaml
# argocd-apps/infra/databases.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgresql
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: postgresql
    targetRevision: "15.x"
    helm:
      valueFiles:
        - https://raw.githubusercontent.com/HV-Hung/homelab-gitops/main/infra/databases/postgresql/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: databases
  syncPolicy: {}  # Manual sync — you approve infra changes
```

### App Application example

```yaml
# argocd-apps/apps/prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-api-service
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/HV-Hung/homelab-gitops
    targetRevision: main
    path: apps/_chart
    helm:
      valueFiles:
        - ../../apps/prod/api-service/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true   # Auto-deploy on git push
```

---

## Sync Policy Summary

| Component | Sync Policy | Reason |
|-----------|-------------|--------|
| Infra (DB, monitoring, ingress) | Manual | Infrequent, deliberate changes |
| ArgoCD self | Manual | Never auto-update your CD tool |
| Dev apps | Automated | Fast iteration |
| Prod apps | Automated + manual gate (optional) | Can add env approval later |

---

## Implementation Checklist

### Bootstrap
- [ ] Create Git repo `homelab-gitops`
- [ ] Write `cluster/namespaces.yaml` (includes vault, cloudflare)
- [ ] Write `bootstrap/argocd-install.sh`
- [ ] Apply namespaces manually
- [ ] Run bootstrap script — ArgoCD is live

### Vault + Vault Secrets Operator
- [x] Read `infra/vault/README.md` for manual bootstrap instructions
- [x] Write `infra/vault/server/values.yaml` with Azure KMS auto-unseal settings
- [x] Write `infra/vault/operator/values.yaml` and `operator-config.yaml`
- [x] Create ArgoCD manifests: `vault-server.yaml`, `vault-operator.yaml`, `vault-operator-config.yaml`
- [ ] Apply `argocd-apps/root.yaml` to ArgoCD
- [ ] Bootstrap `vault-kms-creds` Kubernetes Secret with Azure credentials
- [ ] Sync `vault-server` ArgoCD Application
- [ ] Init Vault (`vault operator init -key-shares=1 -key-threshold=1`), store key safely
- [ ] Setup `kubernetes` auth method and roles in Vault
- [ ] Sync `vault-secrets-operator` and `vault-operator-config` ArgoCD Applications
- [ ] Verify `VaultConnection` is established successfully

### Cloudflare Tunnel
- [ ] Create tunnel in Cloudflare Zero Trust dashboard
- [ ] Store tunnel token in Vault at `secret/infra/cloudflare`
- [ ] Write `infra/cloudflare/values.yaml`
- [ ] Write `infra/cloudflare/tunnel-secret.yaml` (VaultStaticSecret)
- [ ] Apply cloudflare ArgoCD Application, manually sync
- [ ] Verify tunnel shows `Healthy` in Cloudflare dashboard

### Infra
- [ ] Write `infra/ingress/values.yaml` and ArgoCD Application manifest
- [ ] Write `infra/databases/` values for postgresql, redis, rabbitmq
- [ ] Store DB passwords in Vault under `secret/infra/databases/`
- [ ] Write VaultStaticSecrets for each DB credential
- [ ] Write `infra/monitoring/` values for full stack
- [ ] Write `infra/argocd/values.yaml` for self-management
- [ ] Manually sync infra apps — wave order: vault → VSO → ingress+cloudflare → DB → monitoring

### Application Chart
- [ ] Build `apps/_chart/` generic Helm chart
- [ ] Write dev values for each Go service
- [ ] Write prod values for each Go service
- [ ] Store app secrets in Vault under `secret/dev/` and `secret/prod/`
- [ ] Add Application manifests in `argocd-apps/apps/`
- [ ] Verify auto-sync triggers on push

### Validation
- [ ] All namespaces healthy
- [ ] Vault unsealed automatically via Azure Key Vault
- [ ] VaultDynamic/Static Secrets successfully synced to Kubernetes Secrets
- [ ] Cloudflare tunnel shows Healthy, test public domain routing
- [ ] Ingress routing internal traffic
- [ ] DBs reachable from app namespaces
- [ ] Grafana dashboards showing cluster metrics
- [ ] ArgoCD shows all apps `Synced` / `Healthy`
- [ ] Push a dummy change to a dev service — confirm auto-deploy

---

## Notes

- **Version pin everything** — always specify `targetRevision` for charts, never use `latest`
- **Vault unseal keys** — never commit to Git. Store offline (USB, password manager, paper). Losing them means losing all secrets permanently
- **Vault restart = sealed** — on a single node, Vault reseals on every pod restart. Consider automating unseal via a k8s Job that reads keys from an encrypted k8s Secret, or migrate to Transit auto-unseal once Vault is stable
- **Single node** — set `tolerations` and `nodeAffinity` if any infra charts default to multi-node assumptions
- **Backup** — for PostgreSQL on a single node, set up a CronJob to dump to an external location. Also backup Vault's data directory (`/vault/data`) regularly