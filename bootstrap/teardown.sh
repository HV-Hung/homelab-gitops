#!/bin/bash
set -e

echo "⚠️  WARNING: This will DESTROY all resources managed by GitOps."
echo "Are you sure you want to proceed? (yes/no)"
read response
if [ "$response" != "yes" ]; then
    echo "Aborting."
    exit 1
fi

echo "1/4: Deleting ArgoCD Applications and ApplicationSets..."
# Delete root app first so it doesn't recreate children
kubectl delete application gitops-root -n argocd --ignore-not-found
# Delete apps/appsets so ArgoCD actually removes the workloads
kubectl delete applicationsets --all -n argocd --ignore-not-found
kubectl delete applications --all -n argocd --ignore-not-found

echo "2/4: Uninstalling ArgoCD Helm Release..."
helm uninstall argocd -n argocd || echo "ArgoCD helm release not found."

echo "3/4: Deleting Namespaces & PVCs..."
# Deleting namespaces removes all resources inside them, including PVCs
for ns in argocd dev prod databases monitoring ingress cloudflare vault; do
  echo "Deleting namespace $ns..."
  kubectl delete namespace $ns --ignore-not-found
done

echo "4/4: Re-applying base cluster resources..."
# Ensure the base namespaces / storage classes are available for next bootstrap
kubectl apply -f cluster/

echo "✅ Teardown complete. Cluster is clean."
echo "Note: If you plan to re-bootstrap, ensure Azure credentials for Vault are created first!"
