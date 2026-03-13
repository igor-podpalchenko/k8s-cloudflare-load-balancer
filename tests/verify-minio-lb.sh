#!/bin/bash
set -euo pipefail

CTX="${KUBE_CONTEXT:-kubernetes-admin@ovh-k8s-clu1}"
NS="${NAMESPACE:-default}"
API_SVC="${API_SERVICE_NAME:-minio-api}"
CONSOLE_SVC="${CONSOLE_SERVICE_NAME:-minio-console}"

echo "== Pods =="
kubectl --context "$CTX" -n "$NS" get pods -l app=minio-test -o wide

echo "== StatefulSet =="
kubectl --context "$CTX" -n "$NS" get statefulset minio-test

echo "== Service =="
kubectl --context "$CTX" -n "$NS" get svc "$API_SVC" "$CONSOLE_SVC" -o wide

echo "== CF resources =="
kubectl --context "$CTX" get cfss,cfdns,cfcon -A -o wide | rg "NAME|$API_SVC|$CONSOLE_SVC|minio"

echo "== In-cluster health check (/minio/health/ready) =="
kubectl --context "$CTX" -n "$NS" run minio-healthcheck --image=curlimages/curl:8.11.1 --restart=Never --rm -i -- \
  sh -c "curl -sS -o /dev/null -w '%{http_code}\n' http://$API_SVC.$NS.svc.cluster.local:443/minio/health/ready && curl -sS -o /dev/null -w '%{http_code}\n' http://$CONSOLE_SVC.$NS.svc.cluster.local:8443/login"
