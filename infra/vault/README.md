# Vault & Vault Secrets Operator Setup

This directory contains the configurations for deploying HashiCorp Vault inside Kubernetes and setting up HashiCorp Vault Secrets Operator (VSO) to sync secrets to our Kubernetes applications.

Because Vault manages the "keys to the kingdom", its first-time initialization and setup require several manual steps.

## Prerequisites

You need the `az` CLI, `kubectl`, and `vault` CLI installed locally.

## 1. Create Azure Key Vault & Service Principal (For Auto-Unseal)

To prevent Vault from remaining sealed after a pod restart, we use Azure Key Vault to automatically unseal it via the transit system.

1. **Create the Azure Resource Group and Key Vault**:
   ```bash
   az group create --name vault-rg --location southeastasia
   az keyvault create --name "homelab-vault-kv" --resource-group vault-rg --location southeastasia
   ```

2. **Create a cryptographic key inside Key Vault**:
   ```bash
   az keyvault key create --vault-name "homelab-vault-kv" --name "vault-unseal-key" --protection software
   ```

3. **Create a Service Principal for Vault to access the Key Vault**:
   ```bash
   az ad sp create-for-rbac --name "vault-unseal-sp" --skip-assignment
   ```
   *Take note of the `appId`, `password`, and `tenant` in the JSON output.*

4. **Grant the Service Principal access to the Key Vault**:
   ```bash
   # Assign the role at the Key Vault level so it is visible in the Key Vault IAM blade
   az role assignment create --role "Key Vault Crypto Service Encryption User" \
     --assignee "<appId>" \
     --scope "/subscriptions/<subscription-id>/resourceGroups/vault-rg/providers/Microsoft.KeyVault/vaults/homelab-vault-kv"
   ```

5. **Provide the credentials to Vault**:
   Because this is a GitOps repository, **do not commit the Azure Client Secret in plain text**.
   First, create a Kubernetes Secret manually in your cluster:
   ```bash
   kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
   kubectl create secret generic vault-kms-creds -n vault \
     --from-literal=AZURE_TENANT_ID="<tenant-id>" \
     --from-literal=AZURE_CLIENT_ID="<appId>" \
     --from-literal=AZURE_CLIENT_SECRET="<password>"
   ```

   Then, update `infra/vault/server/values.yaml` to reference these secret variables and specify the Key Vault configuration:
   ```yaml
   extraEnvironmentVars:
     VAULT_SEAL_TYPE: "azurekeyvault"
     VAULT_AZUREKEYVAULT_VAULT_NAME: "homelab-vault-kv"
     VAULT_AZUREKEYVAULT_KEY_NAME: "vault-unseal-key"

   extraSecretEnvironmentVars:
     - envName: AZURE_TENANT_ID
       secretName: vault-kms-creds
       secretKey: AZURE_TENANT_ID
     - envName: AZURE_CLIENT_ID
       secretName: vault-kms-creds
       secretKey: AZURE_CLIENT_ID
     - envName: AZURE_CLIENT_SECRET
       secretName: vault-kms-creds
       secretKey: AZURE_CLIENT_SECRET
   ```

## 2. Initialize Vault

After syncing the Vault server deployment using ArgoCD, initialize Vault. Since we rely on Azure Key Vault for auto-unsealing, we can stick to a simple 1 share, 1 threshold for the recovery keys.

1. **Exec into the running Vault pod**:
   ```bash
   kubectl exec -it -n vault vault-0 -- sh
   ```
2. **Initialize Vault**:
   ```bash
   vault operator init -recovery-shares=1 -recovery-threshold=1
   ```
   *IMPORTANT: Save the output! The output contains the **Recovery Key** and the **Initial Root Token**. Save these in a secure offline password manager.* Vault is now initialized and automatically unsealed.

## 3. Configure Kubernetes Auth for Vault Secrets Operator

VSO needs permission to authenticate and read secrets from Vault.

1. **Log in to Vault** using your Initial Root Token:
   ```bash
   vault login <your-root-token>
   ```

2. **Enable Kubernetes Auth**:
   ```bash
   vault auth enable kubernetes
   vault write auth/kubernetes/config \
       kubernetes_host="https://kubernetes.default.svc.cluster.local"
   ```

3. **Create the Policy for VSO**:
   Create a policy file named `vso-policy.hcl`:
   ```hcl
   path "secret/data/*" {
     capabilities = ["read"]
   }
   ```
   Apply the policy:
   ```bash
   vault policy write vso-policy vso-policy.hcl
   ```

4. **Create the Role for VSO**:
   Bind the policy to the service account used by Vault Secrets Operator (usually `vault-secrets-operator-controller-manager` or `default` inside the VSO namespace).
   ```bash
   vault write auth/kubernetes/role/default \
       bound_service_account_names="vso-sa" \
       bound_service_account_namespaces="*" \
       policies=vso-policy \
       ttl=1h
   ```
   *Note: Adjust `bound_service_account_names` to the actual VSO service account name for better security.*

## 4. Deploy Vault Secrets Operator (VSO)

Once the auth setup is complete, you can sync the ArgoCD application for Vault Secrets Operator.

When VSO is deployed, it reads the `VaultConnection` and `VaultAuthGlobal` resources defined in `infra/vault/operator/operator-config.yaml` to establish a connection using the Kubernetes Auth method configured above.

From this point on, your services can create `VaultStaticSecret` manifests, and VSO will dynamically create native Kubernetes Secrets.
