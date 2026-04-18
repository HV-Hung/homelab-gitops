#!/bin/bash

# Apply base cluster resources (namespaces, storage classes, etc.)
kubectl apply -f cluster/

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values infra/argocd/values.yaml \
  --version 9.5.2
