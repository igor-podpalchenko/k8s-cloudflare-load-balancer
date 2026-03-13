#!/bin/bash
set -euo pipefail

CTX="${KUBE_CONTEXT:-kubernetes-admin@ovh-k8s-clu1}"
ACTION="${ACTION:-apply}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/examples/nginx-ingress-test.yaml"
LB_CLASS="${LB_CLASS:-tcp-lb.l3.nu/cloudflared}"
INGRESS_NS="${INGRESS_NS:-ingress-nginx}"

case "$ACTION" in
  apply)
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      -n "$INGRESS_NS" --create-namespace \
      --set controller.service.type=LoadBalancer \
      --set controller.service.loadBalancerClass="$LB_CLASS" \
      --set controller.ingressClassResource.name=nginx \
      --set controller.ingressClass=nginx \
      --wait --timeout 10m

    kubectl --context "$CTX" apply -f "$MANIFEST"

    # Wait until ingress controller address is published.
    for _ in $(seq 1 40); do
      addr="$(kubectl --context "$CTX" -n default get ingress my-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
      if [[ -n "$addr" ]]; then
        break
      fi
      sleep 3
    done

    # Wait for app1/app2/app3 DNS records managed by CF controller.
    for _ in $(seq 1 40); do
      out="$(kubectl --context "$CTX" get cfdns -A -o wide 2>/dev/null || true)"
      if echo "$out" | grep -q 'app1.l3.nu' && echo "$out" | grep -q 'app2.l3.nu' && echo "$out" | grep -q 'app3.l3.nu'; then
        break
      fi
      sleep 3
    done
    ;;
  delete)
    kubectl --context "$CTX" delete -f "$MANIFEST" --ignore-not-found
    helm uninstall ingress-nginx -n "$INGRESS_NS" >/dev/null 2>&1 || true
    ;;
  *)
    echo "Unsupported ACTION: $ACTION (use apply or delete)" >&2
    exit 1
    ;;
esac
