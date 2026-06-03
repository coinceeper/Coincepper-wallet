#!/usr/bin/env bash
# Prints TLS_PIN_SHA256 dart-define fragments: host:sha256(cert_der)
# Usage: ./scripts/extract_tls_pins.sh coinceeper.com agentadmin.duckdns.org
set -euo pipefail
for host in "$@"; do
  hash=$(echo | openssl s_client -connect "${host}:443" -servername "$host" 2>/dev/null \
    | openssl x509 -outform DER 2>/dev/null | openssl dgst -sha256 | awk '{print $2}')
  echo "${host}:${hash}"
done
echo "# Merge: --dart-define=TLS_PIN_SHA256=\$(./scripts/extract_tls_pins.sh host1 host2 | paste -sd, -)"
