#!/usr/bin/env bash
# Pull explorer/RPC keys from production VM .env and apply to local gitignored Flutter config.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_DIR="$ROOT/secrets"
ENV_OUT="$SECRETS_DIR/vm_api_keys.env"
PROJECT="${GCP_PROJECT:-omega-bearing-446811-p5}"
ZONE="${GCP_ZONE:-us-central1-f}"
INSTANCE="${GCP_INSTANCE:-coinceeper}"
REMOTE_ENV="${REMOTE_ENV:-/opt/coinceeper/CC/.env}"

mkdir -p "$SECRETS_DIR"
echo "Fetching keys from $INSTANCE ($PROJECT / $ZONE) ..."
REMOTE_CMD=$(cat <<EOF
set -a
source '$REMOTE_ENV'
set +a
for k in ETHERSCAN_API_KEY BSCSCAN_API_KEY POLYGONSCAN_API_KEY AVALANCHE_API_KEY ARBITRUMSCAN_API_KEY TRONGRID_API_KEY SUBSCAN_API_KEY INFURA_API_KEY alchemy_api_key SOLANA_RPC_URL BSC_RPC_URL XRPL_RPC_URL; do
  v=\${!k}
  if [ -n "\$v" ]; then printf '%s=%s\\n' "\$k" "\$v"; fi
done
EOF
)
gcloud compute ssh "$INSTANCE" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --quiet \
  --command="bash -lc $(printf '%q' "$REMOTE_CMD")" \
  >"$ENV_OUT"

python3 "$ROOT/scripts/apply_pulled_api_keys.py" "$ROOT"

echo "Done. Rebuild the app so dart-defines are picked up."
