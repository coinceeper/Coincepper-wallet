#!/usr/bin/env bash
# Appends CLIENT_HMAC_SECRET and TLS_PIN_SHA256 to ios/Flutter/DartDefines.xcconfig (base64 EXTRA_DART_DEFINES).
# Env: CLIENT_HMAC_SECRET, TLS_PIN_SHA256 (or set in secrets/vm_api_keys.env)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/secrets/vm_api_keys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
HMAC="${CLIENT_HMAC_SECRET:-}"
PINS="${TLS_PIN_SHA256:-}"
if [[ -z "$HMAC" && -z "$PINS" ]]; then
  echo "Set CLIENT_HMAC_SECRET and/or TLS_PIN_SHA256 in environment or $ENV_FILE"
  exit 1
fi
XCCONFIG="${ROOT}/ios/Flutter/DartDefines.xcconfig"
pairs=()
[[ -n "$HMAC" ]] && pairs+=("CLIENT_HMAC_SECRET=${HMAC}")
[[ -n "$PINS" ]] && pairs+=("TLS_PIN_SHA256=${PINS}")
joined=$(IFS=,; echo "${pairs[*]}")
b64=$(printf '%s' "$joined" | base64 | tr -d '\n')
echo "# Wallet build defines (generated)" >> "$XCCONFIG"
echo "WALLET_EXTRA_DART_DEFINES=${b64}" >> "$XCCONFIG"
echo "DART_DEFINES=\$(DART_DEFINES),\$(WALLET_EXTRA_DART_DEFINES)" >> "$XCCONFIG"
echo "Updated $XCCONFIG"
