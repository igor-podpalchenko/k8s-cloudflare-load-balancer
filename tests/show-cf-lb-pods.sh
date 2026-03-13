#!/bin/bash
set -euo pipefail

CTX="${KUBE_CONTEXT:-kubernetes-admin@ovh-k8s-clu1}"

echo "--------------------------------" "cfss"  "--------------------------------"
kubectl --context "$CTX" get cfss -A  --ignore-not-found
echo "--------------------------------" "vrrps"  "--------------------------------"
kubectl --context "$CTX" get vrrps -A  --ignore-not-found
echo "--------------------------------" "vpod"  "--------------------------------"
kubectl --context "$CTX" get vpod -A  --ignore-not-found
echo "--------------------------------" "cfdns"  "--------------------------------"
kubectl --context "$CTX" get cfdns -A  --ignore-not-found
echo "--------------------------------" "cfcon"  "--------------------------------"
kubectl --context "$CTX" get cfcon -A  --ignore-not-found
echo "--------------------------------" "svc"  "--------------------------------"
kubectl --context kubernetes-admin@ovh-k8s-clu1 get svc -A

echo "--------------------------------" "ingress"  "--------------------------------"
kubectl --context kubernetes-admin@ovh-k8s-clu1 get ingress -A --ignore-not-found
echo "--------------------------------" "GatewayClass"  "--------------------------------"
kubectl --context kubernetes-admin@ovh-k8s-clu1 get GatewayClass -A --ignore-not-found
echo "--------------------------------" "Gateway"  "--------------------------------"
kubectl --context kubernetes-admin@ovh-k8s-clu1 get Gateway -A --ignore-not-found
echo "--------------------------------" "HTTPRoute"  "--------------------------------"
kubectl --context kubernetes-admin@ovh-k8s-clu1 get HTTPRoute -A --ignore-not-found
