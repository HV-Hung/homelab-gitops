# Terraform Configuration for HomeLab

This directory contains the Terraform modules to configure the identity and secrets management for the HomeLab GitOps cluster, following the principle of least privilege.

## Structure

- `azure/`: Manages Azure AD application, Service Principal, and Key Vault. Run this **first** (one-time setup or on rotation).
- `vault/`: Manages HashiCorp Vault configuration (KV engine, auth methods, policies, roles). Run this **after** Vault is deployed and unsealed.

## 1. Setup Azure Key Vault (Unseal mechanism)

1. Navigate to the `azure/` directory:
   ```bash
   cd azure
   ```
2. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```
3. Export the outputs as a Kubernetes secret in the `vault` namespace BEFORE deploying ArgoCD/Vault:
   ```bash
   kubectl create namespace vault
   kubectl create secret generic vault-kms-creds -n vault \
     --from-literal=AZURE_TENANT_ID=$(terraform output -raw azure_tenant_id) \
     --from-literal=AZURE_CLIENT_ID=$(terraform output -raw azure_client_id) \
     --from-literal=AZURE_CLIENT_SECRET=$(terraform output -raw azure_client_secret)
   ```

## 2. Configure Vault (Auth & Least Privilege Policies)

Once Vault is deployed via ArgoCD and initialized/unsealed (which uses the Key Vault configured above):

1. Export your root token so Terraform can authenticate:
   ```bash
   export VAULT_ADDR="http://vault.hungops.tech" # Or use port-forwarding: http://localhost:8200
   export VAULT_TOKEN="<your-root-token>"
   ```
2. Navigate to the `vault/` directory:
   ```bash
   cd ../vault
   ```
3. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```

## 3. Populate Secrets Manually

After Vault is configured, populate the secrets manually:

```bash
# Databases need all 3
vault kv put secret/admin DB_PASSWORD="xxx"
vault kv put dev DB_PASSWORD="yyy"
vault kv put prod DB_PASSWORD="zzz"

# Cloudflare
vault kv put secret/cloudflare token="<your-cloudflare-tunnel-token>"
```
