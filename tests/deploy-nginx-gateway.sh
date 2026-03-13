#!/bin/bash
set -euo pipefail

CTX="${KUBE_CONTEXT:-kubernetes-admin@ovh-k8s-clu1}"
ACTION="${ACTION:-apply}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/examples/nginx-via-gateway.yaml"
GATEWAY_SERVICE_TYPE="${GATEWAY_SERVICE_TYPE:-ClusterIP}"

case "$ACTION" in
  apply)
    curl -fsSL https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/main/deploy/default/deploy.yaml \
      | sed 's/namespace: nginx-gateway/namespace: default/g' \
      | kubectl --context "$CTX" apply -f -

    # Wait for GatewayClass creation by nginx gateway fabric.
    for _ in $(seq 1 40); do
      if kubectl --context "$CTX" get gatewayclass nginx >/dev/null 2>&1; then
        break
      fi
      sleep 3
    done

    # Keep Gateway dataplane service type explicit (default ClusterIP).
    kubectl --context "$CTX" -n default patch nginxproxy.gateway.nginx.org nginx-gateway-proxy-config \
      --type=merge \
      -p "{\"spec\":{\"kubernetes\":{\"service\":{\"type\":\"$GATEWAY_SERVICE_TYPE\"}}}}" >/dev/null 2>&1 || true

    kubectl --context "$CTX" apply -f "$MANIFEST"
    ;;
  delete)
    kubectl --context "$CTX" delete -f "$MANIFEST" --ignore-not-found
    kubectl --context "$CTX" -n default delete deploy nginx-gateway --ignore-not-found >/dev/null 2>&1 || true
    kubectl --context "$CTX" delete gatewayclass nginx --ignore-not-found >/dev/null 2>&1 || true
    ;;
  *)
    echo "Unsupported ACTION: $ACTION (use apply or delete)" >&2
    exit 1
    ;;
esac
