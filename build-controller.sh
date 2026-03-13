#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/bin}"
OUT_BIN="${OUT_BIN:-$OUT_DIR/cf-lb-controller}"

mkdir -p "$OUT_DIR"

echo "Building controller binary..."
echo "  output: $OUT_BIN"
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o "$OUT_BIN" ./cmd/controller

echo "Done: $OUT_BIN"
