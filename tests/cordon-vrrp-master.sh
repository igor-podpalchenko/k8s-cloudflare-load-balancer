#!/bin/bash
set -euo pipefail

CTX="kubernetes-admin@ovh-k8s-clu1"
NS="kube-system"

master_line="$(kubectl --context "$CTX" -n "$NS" get vpod -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.vipAssigned}{"|"}{.status.nodeName}{"\n"}{end}' | awk -F'|' '$2=="true" {print $1 "|" $3; exit}')"

if [[ -z "$master_line" ]]; then
  echo "No VRRP master pod found (vipAssigned=true) in $NS/vpod."
  echo "Current vpod objects:"
  kubectl --context "$CTX" -n "$NS" get vpod -o wide || true
  exit 1
fi

MASTER_POD="${master_line%%|*}"
MASTER_NODE="${master_line##*|}"

echo "Current VRRP master pod: $MASTER_POD"
echo "Current VRRP master node: $MASTER_NODE"

echo "[1/4] Cordon node $MASTER_NODE"
kubectl --context "$CTX" cordon "$MASTER_NODE"

echo "[2/4] Drain node $MASTER_NODE (DaemonSet pods are ignored)"
kubectl --context "$CTX" drain "$MASTER_NODE" --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=5m

echo "[3/4] Delete VRRP master pod $MASTER_POD to force failover"
kubectl --context "$CTX" -n "$NS" delete pod "$MASTER_POD"

echo "[4/4] Current VRRP status"
kubectl --context "$CTX" -n "$NS" get vrrps,vpod -o wide
