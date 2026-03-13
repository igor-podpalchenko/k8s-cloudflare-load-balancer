#!/bin/bash

helm upgrade --install cf-lb-controller ./charts/cf-lb-controller \
  -n kube-system \
  -f ./charts/cf-lb-controller/values.private.yaml \
  --wait --timeout 10m

tests/deploy-nginx-lb-no-class.sh
tests/deploy-nginx-lb-with-class.sh
tests/deploy-nginx-ingress.sh
tests/deploy-nginx-gateway.sh

