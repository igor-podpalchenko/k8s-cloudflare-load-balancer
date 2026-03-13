#!/bin/bash
set -euo pipefail

CTX="kubernetes-admin@ovh-k8s-clu1"

nodes="$(kubectl --context "$CTX" get nodes -o jsonpath='{range .items[?(@.spec.unschedulable==true)]}{.metadata.name}{"\n"}{end}')"

if [[ -z "$nodes" ]]; then
  echo "No cordoned nodes found."
  exit 0
fi

echo "Uncordoning nodes:"
printf '%s\n' "$nodes"

while IFS= read -r node; do
  [[ -z "$node" ]] && continue
  kubectl --context "$CTX" uncordon "$node"
done <<< "$nodes"

echo "Done. Node states:"
kubectl --context "$CTX" get nodes
