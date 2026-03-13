#!/bin/bash

helm upgrade --install cf-lb-controller ./charts/k8s-cloudflare-load-balancer \
  -n kube-system \
  -f ./charts/k8s-cloudflare-load-balancer/values.private.yaml \
  --wait --timeout 10m

tests/deploy-nginx-lb-no-class.sh
tests/deploy-nginx-lb-with-class.sh
tests/deploy-nginx-ingress.sh
tests/deploy-nginx-gateway.sh

