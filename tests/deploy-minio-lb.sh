#!/bin/bash
set -euo pipefail

CTX="${KUBE_CONTEXT:-kubernetes-admin@ovh-k8s-clu1}"
NS="${NAMESPACE:-default}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT_DIR/examples/minio-lb-test.yaml"

echo "Deleting existing MinIO resources (including PVC/PV-backed data)..."
kubectl --context "$CTX" -n "$NS" delete statefulset minio-test --ignore-not-found --wait=true
kubectl --context "$CTX" -n "$NS" delete svc minio-api minio-console minio-hl minio-test --ignore-not-found
kubectl --context "$CTX" -n "$NS" delete secret minio-creds --ignore-not-found
kubectl --context "$CTX" -n "$NS" delete pvc data-minio-test-0 data-minio-test-1 data-minio-test-2 --ignore-not-found --wait=true

for pv in $(kubectl --context "$CTX" get pv -o custom-columns=NAME:.metadata.name,NS:.spec.claimRef.namespace,CLAIM:.spec.claimRef.name --no-headers 2>/dev/null | awk '$2=="'"$NS"'" && $3 ~ /^data-minio-test-/ {print $1}'); do
  kubectl --context "$CTX" delete pv "$pv" --ignore-not-found
done

echo "Applying MinIO test manifest..."
kubectl --context "$CTX" -n "$NS" apply -f "$FILE"
kubectl --context "$CTX" -n "$NS" rollout status statefulset/minio-test --timeout=10m
kubectl --context "$CTX" -n "$NS" get svc minio-api minio-console -o wide

echo "Access Key: minioadmin"
echo "Secret Key: minioadmin"
echo "API port: 443"
echo "Console port: 8443"
