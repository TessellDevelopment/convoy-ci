#!/usr/bin/env bash
# usage: ./gen-admin-kubeconfig.sh > admin-snippet.yaml
# then manually merge into ~/.kube/config

set -euo pipefail

TAILSCALE_BIN="${TAILSCALE_BIN:-}"
if [[ -z "$TAILSCALE_BIN" ]]; then
  if command -v tailscale >/dev/null 2>&1; then
    TAILSCALE_BIN="$(command -v tailscale)"
  elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
    TAILSCALE_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  else
    echo "tailscale CLI not found. Set TAILSCALE_BIN or install the CLI." >&2
    exit 1
  fi
fi

nodes=$("$TAILSCALE_BIN" status | grep -E 'prod.*admin' | awk '{print $1, $2}')

if [[ -z "$nodes" ]]; then
  echo "No prod admin nodes found in tailscale status" >&2
  echo "Available prod nodes:" >&2
  "$TAILSCALE_BIN" status | grep prod >&2
  exit 1
fi

echo "clusters:"
while read -r ip host; do
  cat <<EOF
- cluster:
    insecure-skip-tls-verify: true
    server: http://${ip}
  name: ${host}
EOF
done <<< "$nodes"

echo ""
echo "contexts:"
while read -r ip host; do
  cat <<EOF
- context:
    cluster: ${host}
    namespace: default
    user: ${host}-user
  name: ${host}
EOF
done <<< "$nodes"

echo ""
echo "users:"
while read -r ip host; do
  cat <<EOF
- name: ${host}-user
  user: {}
EOF
done <<< "$nodes"