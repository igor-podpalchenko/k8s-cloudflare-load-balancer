# k8s-cloudflare-load-balancer

This k8s controller, that reduces your cloud (GKE, Azure, AWS, OVH) costs on Load balancer and public IP to zero.

Please donate for new features development. It's intentionally left as "developer friendly" version with all features, but has no extras. If you need extra functionality with dashboard, advanced configuration, monitoring, logging and advanced security, please contact me for paid version: igor@podpalchenko.com

Donate to (In UAH):

[![Donate via Monobank](https://img.shields.io/badge/Donate-Monobank-000000?style=for-the-badge)](https://send.monobank.ua/jar/3ZsxT3o6qB)

Kubernetes controller that implements a private `LoadBalancer` class using Cloudflare Tunnel + DNS.

When a `Service` is created with:

- `spec.type: LoadBalancer`
- `spec.loadBalancerClass: tcp-lb.l3.nu/cloudflared` (or your configured class)

the controller does the following:

1. Generates a hostname: `<8-random-chars>.<PRIMARY_DOMAIN>`.
2. Creates a Cloudflare Tunnel using API token auth.
3. Ensures a proxied Cloudflare DNS CNAME record to `<tunnel-id>.cfargotunnel.com`.
4. Creates a token `Secret` in the same namespace as the Service.
5. Creates/updates a `cloudflared` `StatefulSet` with `TUNNEL_REPLICAS` replicas.
6. Adds finalizer + annotations to track resources.
7. On Service deletion, removes DNS record, tunnel, secret, and cloudflared workload.

If VIP mode is enabled (`VIP_ADDRESS`), controller also maintains Keepalived + HAProxy DaemonSet config and status CRDs.

Gateway API integration is also supported (appended, legacy Service flow unchanged). When a managed LB Service backs a Gateway address, hostnames from Gateway listeners and HTTPRoutes are also published to Cloudflare DNS/tunnel routes.

## Required Cloudflare token permissions

Use a token with both permissions:

- `Account: Cloudflare Tunnel Edit`
- `Zone: DNS Edit`

## Cloudflare supported proxy ports

HTTP ports supported by Cloudflare:

- `80`
- `8080`
- `8880`
- `2052`
- `2082`
- `2086`
- `2095`

HTTPS ports supported by Cloudflare:

- `443`
- `2053`
- `2083`
- `2087`
- `2096`
- `8443`

Supported but caching disabled:

- `2052`
- `2053`
- `2082`
- `2083`
- `2086`
- `2087`
- `2095`
- `2096`
- `8880`
- `8443`

For MinIO tests in this repo:

- API is exposed via LB Service port `443` (to container `9000`)
- Console is exposed via LB Service port `8443` (to container `9001`)

## Deploy (Helm only)

1. Prepare private values (not committed):

```bash
# file is provided and gitignored:
ls charts/k8s-cloudflare-load-balancer/values.private.yaml
```

2. Set real secrets in `charts/k8s-cloudflare-load-balancer/values.private.yaml`:

- `config.cfApiToken`
- `config.cfAccountId`
- `config.vipAuthPass`

Do not commit `charts/k8s-cloudflare-load-balancer/values.private.yaml`. It is intentionally gitignored.

3. Install from chart:

```bash
helm upgrade --install cf-lb-controller ./charts/k8s-cloudflare-load-balancer \
  -n kube-system --create-namespace \
  -f charts/k8s-cloudflare-load-balancer/values.yaml \
  -f charts/k8s-cloudflare-load-balancer/values.private.yaml
```

CRDs are bundled in `charts/k8s-cloudflare-load-balancer/crds` and are installed automatically by Helm.

## Deploy From OCI

Published OCI chart:

- `oci://ghcr.io/igor-podpalchenko/charts/k8s-cloudflare-load-balancer`

Install from GHCR:

```bash
helm upgrade --install cf-lb-controller oci://ghcr.io/igor-podpalchenko/charts/k8s-cloudflare-load-balancer \
  --version 0.1.0 \
  -n kube-system --create-namespace \
  -f charts/k8s-cloudflare-load-balancer/values.private.yaml
```

If you want to inspect the packaged chart stored in this repo, it is written under:

- `charts/k8s-cloudflare-load-balancer/`

## Build artifacts

All local build artifacts are written to `bin/`.

- Build controller binary:

```bash
./build-controller.sh
```

Output:

- `bin/cf-lb-controller`

- Package + publish Helm chart to OCI:

```bash
./publish-chart-oci.sh
```

Output package:

- `bin/k8s-cloudflare-load-balancer-<version>.tgz`

Quick test install (controllers + examples):

```bash
tests/deploy-nginx-lb-no-class.sh
tests/deploy-nginx-lb-with-class.sh
tests/deploy-nginx-ingress.sh
tests/deploy-nginx-gateway.sh
```

## Helm values (important)

Main service handling values:

- `config.lbClass`: class owned by this controller (`tcp-lb.l3.nu/cloudflared`)
- `config.allowClasslessLb`: lets reconcile manage classless LB services (`true`/`false`)
- `config.tunnelReplicas`: cloudflared replicas (`>=2`)
- `config.cloudflaredImage`: cloudflared image
- `config.vipAddress`, `config.vipCidr`, `config.vipRouterId`, `config.vipAuthPass`: VIP/VRRP mode
  - public defaults use `CHANGE_ME` for `vipAuthPass`; replace it before real deployment

Mutating webhook values:

- `webhook.labels.cf-lb-enabled` (default `"true"`)
  - this label is applied to webhook resources (`MutatingWebhookConfiguration` / webhook cert secret)
  - chart treats this label as webhook switch:
  - `"true"` => webhook resources rendered and active
  - `"false"` => webhook resources not rendered (disabled)
- `webhook.port` (default `9443`)
- `webhook.failurePolicy` (default `Ignore`)
  - `Ignore` is safer for availability.
  - `Fail` is stricter but can block service creates if webhook is unavailable.
- `webhook.webhooks[]` (per-hook definitions)
  - no Service label is required
  - default `objectSelector` is empty, so webhook applies to matching CREATE Service requests

Example webhook-enabled label:

```yaml
webhook:
  labels:
    cf-lb-enabled: "true"
  webhooks:
    - name: service-default-class.tcp-lb.l3.nu
      admissionReviewVersions: [v1]
      failurePolicy: Ignore
      matchPolicy: Equivalent
      reinvocationPolicy: Never
      namespaceSelector: {}
      objectSelector: {}
      rules:
        - apiGroups: [""]
          apiVersions: [v1]
          operations: [CREATE]
          resources: [services]
          scope: "*"
      clientConfig:
        path: /mutate-v1-service
        port: 443
```

Example override:

```bash
helm upgrade --install cf-lb-controller ./charts/k8s-cloudflare-load-balancer \
  -n kube-system --create-namespace \
  -f charts/k8s-cloudflare-load-balancer/values.private.yaml \
  --set webhook.labels.cf-lb-enabled=true \
  --set webhook.failurePolicy=Ignore
```

Disable webhook:

```bash
helm upgrade --install cf-lb-controller ./charts/k8s-cloudflare-load-balancer \
  -n kube-system --create-namespace \
  -f charts/k8s-cloudflare-load-balancer/values.private.yaml \
  --set webhook.labels.cf-lb-enabled=false
```

## Test scripts

Use project scripts under `tests/`:

- `tests/deploy-nginx-lb-no-class.sh`
- `tests/deploy-nginx-lb-with-class.sh`
- `tests/deploy-nginx-ingress.sh`
- `tests/deploy-nginx-gateway.sh`
- `tests/uninstall-all.sh`
- `tests/show-cf-lb-pods.sh`

Script behavior:

- `tests/deploy-nginx-ingress.sh`
  - installs/updates `ingress-nginx` Helm chart automatically
  - controller service is `LoadBalancer` with class `tcp-lb.l3.nu/cloudflared`
  - waits for ingress address and DNS records `app1.l3.nu`, `app2.l3.nu`, `app3.l3.nu`
- `tests/deploy-nginx-gateway.sh`
  - installs nginx gateway fabric controller automatically
  - defaults gateway dataplane service type to `ClusterIP` (to avoid extra cloud LBs)
  - override when needed:
    - `GATEWAY_SERVICE_TYPE=LoadBalancer tests/deploy-nginx-gateway.sh`
- `tests/uninstall-all.sh`
  - removes workloads, controllers, webhook resources, CRs/CRDs, `GatewayClass nginx`, and test namespaces
  - clears `tcp-lb.l3.nu/cloudflare-finalizer` from Services if needed

Ingress test manifest contains hosts:

- `app1.l3.nu`
- `app2.l3.nu`
- `app3.l3.nu`

Manual examples:

```bash
kubectl apply -f examples/loadbalancer-service.yaml
kubectl apply -f examples/nginx-lb-test.yaml
kubectl apply -f examples/nginx-lb-test-no-lb-class.yaml
kubectl apply -f examples/nginx-ingress-test.yaml
kubectl apply -f examples/nginx-via-gateway.yaml
```

## Gateway API notes

- Supported discovery for hostname publication:
  - `gateway.networking.k8s.io/v1` `Gateway`
  - `gateway.networking.k8s.io/v1` `HTTPRoute`
  - fallback watch support for `v1beta1 HTTPRoute` and `v1alpha2 TCPRoute`
- Existing Service/Ingress behavior is unchanged.
- If Gateway API CRDs are not installed, controller runs normally and skips Gateway augmentation.
- Gateway controller service type is controlled by nginx gateway `NginxProxy` config (`nginx-gateway-proxy-config`).
  - in this repo test flow, default is `ClusterIP` to avoid creating additional cloud-provider LBs
  - if set to `LoadBalancer`, gateway service (for example `my-gw-nginx`) will be picked up by this controller and published through Cloudflare
- New example:
  - `examples/nginx-via-gateway.yaml`

## Service annotations managed by controller

- `tcp-lb.l3.nu/managed=true`
- `tcp-lb.l3.nu/tunnel-id`
- `tcp-lb.l3.nu/tunnel-name`
- `tcp-lb.l3.nu/dns-name`
- `tcp-lb.l3.nu/tunnel-token-secret`
- `tcp-lb.l3.nu/cloudflared-deployment`
- `tcp-lb.l3.nu/resource-id`
- `tcp-lb.l3.nu/loadbalancer-class`
- `tcp-lb.l3.nu/created-at`

## CRDs exposed by controller

- `cloudflareservicestatuses.tcp-lb.l3.nu` (shortname: `cfss`)
  - includes tunnel metadata, connector pod statuses, and Cloudflare DNS record details per managed service.
- `vrrpstatuses.tcp-lb.l3.nu` (shortname: `vrrps`)
  - includes Keepalived/HAProxy (VRRP) pod IPs and statuses.
- `cloudflareconnectors.tcp-lb.l3.nu` (shortname: `cfcon`)
  - one row per cloudflared connector pod.
- `cloudflarednsrecords.tcp-lb.l3.nu` (shortname: `cfdns`)
  - one row per DNS record tracked by the controller.
- `vrrppods.tcp-lb.l3.nu` (shortname: `vpod`)
  - one row per VRRP pod.

Examples:

```bash
kubectl get cfss -A
kubectl get cfcon -A
kubectl get cfdns -A
kubectl -n kube-system get vpod
kubectl --context kubernetes-admin@ovh-k8s-clu1 get vrrps,vpod,cfdns,cfcon -A -o wide
```

Full status command:

```bash
kubectl --context kubernetes-admin@ovh-k8s-clu1 get cfss,vrrps,vpod,cfdns,cfcon -A -o wide
```

Find which VRRP pod currently has the VIP assigned:

```bash
for p in $(kubectl -n kube-system get pods -l app.kubernetes.io/name=cf-lb-vip -o name | sed 's#pod/##'); do
  echo "== $p =="
  kubectl -n kube-system exec "$p" -c keepalived -- sh -c "ip -o addr show | grep -w '10.83.0.250' || true"
done
```

## VRRP failover test (cordon/drain)

Use this flow to validate VRRP ownership switch.

```bash
# Baseline (note: no space after comma)
kubectl --context kubernetes-admin@ovh-k8s-clu1 -n kube-system get vrrps,vpod -o wide

# Cordon + drain current owner node
kubectl --context kubernetes-admin@ovh-k8s-clu1 cordon <owner-node>
kubectl --context kubernetes-admin@ovh-k8s-clu1 drain <owner-node> --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=5m

# Important: drain does not evict DaemonSet pods, so force VRRP failover by deleting the owner DS pod
kubectl --context kubernetes-admin@ovh-k8s-clu1 -n kube-system delete pod <owner-vrrp-pod>

# Watch ownership move (macOS often has no `watch`)
while true; do
  date
  kubectl --context kubernetes-admin@ovh-k8s-clu1 -n kube-system get vpod -o wide
  echo "-----"
  sleep 2
done

# Restore node after test
kubectl --context kubernetes-admin@ovh-k8s-clu1 uncordon <owner-node>
```

Helper scripts:

- `tests/cordon-vrrp-master.sh`
- `tests/uncordon-all-nodes.sh`

## Keepalived + HAProxy (VRRP) example

An optional baseline example is provided at:

- `examples/keepalived-haproxy-vrrp.yaml`

This example uses a host-network `DaemonSet` with Keepalived VRRP and HAProxy TCP frontend. Update interface, VIP, backend service names, and security settings before production use.

## Notes

- `cloudflared` pods run with remote-managed tunnel token mode (`tunnel run --token ...`).
- `cloudflared` StatefulSet name uses `cf-lb-cloudflared-<5-char-id>`, pods are ordinal (`...-0`, `...-1`), and token secret uses `cf-lb-token-<5-char-id>`.
- `cloudflared` replicas use required pod anti-affinity on `kubernetes.io/hostname`.
- Controller chart defaults to `replicaCount: 2` with leader-election enabled and pod anti-affinity (one active leader, one standby).
- Controller-created resources are labeled with `cf-lb-component=<component>`.
- DNS record created is proxied CNAME (`ttl: 1`, automatic).
- VIP DaemonSet reload is hash-driven (`tcp-lb.l3.nu/config-hash`) to avoid stale mixed HAProxy configs.
- Helper scripts resolve repository paths dynamically, so the repo can be cloned anywhere.
- The implementation is minimal and intended as a foundation for hardening (status conditions/events, retries/backoff tuning, admission validation, and metrics).
