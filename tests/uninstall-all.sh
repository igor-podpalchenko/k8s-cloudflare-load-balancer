#!/bin/bash
set -euo pipefail

CTX="${KUBE_CONTEXT:-kubernetes-admin@ovh-k8s-clu1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[1/9] Delete example manifests"
kubectl --context "$CTX" delete -f "$ROOT_DIR/examples/nginx-ingress-test.yaml" --ignore-not-found || true
kubectl --context "$CTX" delete -f "$ROOT_DIR/examples/nginx-via-gateway.yaml" --ignore-not-found || true
kubectl --context "$CTX" delete -f "$ROOT_DIR/examples/nginx-lb-test.yaml" --ignore-not-found || true
kubectl --context "$CTX" delete -f "$ROOT_DIR/examples/nginx-lb-test-no-lb-class.yaml" --ignore-not-found || true
kubectl --context "$CTX" delete -f "$ROOT_DIR/examples/minio-lb-test.yaml" --ignore-not-found || true

echo "[2/9] Remove ingress/gateway API objects"
kubectl --context "$CTX" delete ingress -A --all --ignore-not-found || true
kubectl --context "$CTX" delete gatewayclass nginx --ignore-not-found || true
kubectl --context "$CTX" delete gateway -A --all --ignore-not-found || true
kubectl --context "$CTX" delete httproute -A --all --ignore-not-found || true
kubectl --context "$CTX" delete grpcroute -A --all --ignore-not-found || true
kubectl --context "$CTX" delete referencegrant -A --all --ignore-not-found || true

echo "[3/9] Uninstall Helm releases (if present)"
helm uninstall cf-lb-controller -n kube-system >/dev/null 2>&1 || true
helm uninstall ingress-nginx -n ingress-nginx >/dev/null 2>&1 || true

echo "[4/9] Delete known controller resources"
kubectl --context "$CTX" -n kube-system delete deploy -l app.kubernetes.io/name=cf-lb-controller --ignore-not-found || true
kubectl --context "$CTX" -n kube-system delete svc cf-lb-controller-webhook --ignore-not-found || true
kubectl --context "$CTX" -n kube-system delete ds cf-lb-vip --ignore-not-found || true
kubectl --context "$CTX" -n default delete deploy nginx-gateway --ignore-not-found || true
kubectl --context "$CTX" delete mutatingwebhookconfiguration,validatingwebhookconfiguration -A -l app.kubernetes.io/name=cf-lb-controller --ignore-not-found || true

echo "[5/9] Delete cloudflared managed resources"
kubectl --context "$CTX" delete svc -A -l app.kubernetes.io/name=cloudflared --ignore-not-found || true
kubectl --context "$CTX" delete deploy -A -l app.kubernetes.io/name=cloudflared --ignore-not-found || true
kubectl --context "$CTX" delete sts -A -l app.kubernetes.io/name=cloudflared --ignore-not-found || true
kubectl --context "$CTX" delete secret -A -l app.kubernetes.io/name=cloudflared --ignore-not-found || true

echo "[6/9] Clear service finalizers (tcp-lb.l3.nu/cloudflare-finalizer)"
kubectl --context "$CTX" get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.metadata.finalizers}{"\n"}{end}' 2>/dev/null \
  | grep 'tcp-lb.l3.nu/cloudflare-finalizer' \
  | awk '{print $1" "$2}' \
  | while read -r ns name; do
      [[ -z "${ns:-}" || -z "${name:-}" ]] && continue
      kubectl --context "$CTX" -n "$ns" patch svc "$name" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
      kubectl --context "$CTX" -n "$ns" delete svc "$name" --ignore-not-found >/dev/null 2>&1 || true
    done || true

echo "[7/9] Delete custom resources and CRDs"
kubectl --context "$CTX" delete cfss,cfcon,cfdns,vrrps,vpod -A --all --ignore-not-found || true
kubectl --context "$CTX" delete crd \
  cloudflareservicestatuses.tcp-lb.l3.nu \
  cloudflareconnectors.tcp-lb.l3.nu \
  cloudflarednsrecords.tcp-lb.l3.nu \
  vrrpstatuses.tcp-lb.l3.nu \
  vrrppods.tcp-lb.l3.nu \
  --ignore-not-found || true

echo "[8/9] Delete test namespaces"
kubectl --context "$CTX" delete ns ingress-nginx --ignore-not-found || true
kubectl --context "$CTX" delete ns nginx-gateway --ignore-not-found || true

echo "[9/9] Force-delete lingering cf-lb pods"
kubectl --context "$CTX" -n kube-system delete pod -l app.kubernetes.io/name=cf-lb-vip --force --grace-period=0 --ignore-not-found || true
kubectl --context "$CTX" delete pod -A -l app.kubernetes.io/name=cloudflared --force --grace-period=0 --ignore-not-found || true

echo
echo "Cleanup finished. Current namespaces:"
kubectl --context "$CTX" get ns
