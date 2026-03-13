#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$ROOT_DIR/charts/k8s-cloudflare-load-balancer}"
OCI_REPO="${OCI_REPO:-oci://ghcr.io/igor-podpalchenko/charts}"
CHART_NAME="${CHART_NAME:-k8s-cloudflare-load-balancer}"
CHART_VERSION="${CHART_VERSION:-}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/bin}"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but not found in PATH" >&2
  exit 1
fi

if [[ ! -f "$CHART_DIR/Chart.yaml" ]]; then
  echo "Chart.yaml not found: $CHART_DIR/Chart.yaml" >&2
  exit 1
fi

if [[ -z "$CHART_VERSION" ]]; then
  CHART_VERSION="$(awk -F': *' '$1=="version"{print $2; exit}' "$CHART_DIR/Chart.yaml" | tr -d '"' | tr -d "'")"
fi

if [[ -z "$CHART_VERSION" ]]; then
  echo "Could not determine chart version from $CHART_DIR/Chart.yaml" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Packaging chart:"
echo "  chart:   $CHART_DIR"
echo "  version: $CHART_VERSION"
helm package "$CHART_DIR" --version "$CHART_VERSION" --destination "$OUT_DIR"

PKG_FILE="$OUT_DIR/$CHART_NAME-$CHART_VERSION.tgz"
if [[ ! -f "$PKG_FILE" ]]; then
  echo "Expected package file not found: $PKG_FILE" >&2
  exit 1
fi

echo "Pushing chart:"
echo "  package: $PKG_FILE"
echo "  target:  $OCI_REPO"
helm push "$PKG_FILE" "$OCI_REPO"

echo
 echo "Published:"
echo "  ${OCI_REPO#oci://}/$CHART_NAME:$CHART_VERSION"
