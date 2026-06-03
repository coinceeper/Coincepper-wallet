#!/usr/bin/env bash
# Fails if release-critical dart-defines are missing (CI / pre-release).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/secrets/vm_api_keys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
HMAC="${CLIENT_HMAC_SECRET:-}"
PINS="${TLS_PIN_SHA256:-}"
if [[ -z "$HMAC" ]]; then
  echo "Missing CLIENT_HMAC_SECRET (env or $ENV_FILE)"
  exit 1
fi
if [[ -z "$PINS" ]]; then
  echo "Missing TLS_PIN_SHA256 (env or $ENV_FILE)"
  exit 1
fi
echo "Wallet build secrets OK (HMAC + TLS pins present)"
