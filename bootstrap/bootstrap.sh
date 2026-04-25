#!/bin/bash

# Apply base cluster resources (namespaces, storage classes, etc.)
kubectl apply -f cluster/

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values infra/argocd/values.yaml \
  --version 9.5.2

echo "Waiting for ArgoCD server to be ready..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=90s

echo "Applying GitOps root application..."
kubectl apply -f bootstrap/root.yaml
