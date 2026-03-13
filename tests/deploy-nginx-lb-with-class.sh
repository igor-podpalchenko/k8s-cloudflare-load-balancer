#!/bin/bash
set -euo pipefail

CTX="${KUBE_CONTEXT:-kubernetes-admin@ovh-k8s-clu1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT_DIR/examples/nginx-lb-test.yaml"

kubectl --context "$CTX" -n default apply -f "$FILE"
kubectl --context "$CTX" -n default get svc nginx-with-class -o wide
