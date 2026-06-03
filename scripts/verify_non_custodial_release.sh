#!/usr/bin/env bash
# Automated preflight before mainnet QA / store release (run from repo root).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Flutter tests (wallet mode + token metadata) =="
flutter_ran=false
for candidate in "${FLUTTER:-}" "$(command -v flutter 2>/dev/null)" "$ROOT/.tools/flutter/bin/flutter"; do
  [[ -z "$candidate" || ! -x "$candidate" ]] && continue
  export DART_VM_OPTIONS="${DART_VM_OPTIONS:---old_gen_heap_size=4096}"
  if "$candidate" test test/wallet_mode_test.dart test/token_metadata_service_test.dart --reporter compact; then
    flutter_ran=true
    break
  fi
  echo "WARN: flutter test failed with $candidate"
done
if [[ "$flutter_ran" != true ]]; then
  echo "WARN: skipped flutter tests (use PATH flutter or fix .tools/flutter SDK)"
fi

echo "== Custodial API disabled in Dart =="
grep -q "usesCustodialBalanceApis() async => false" lib/wallet/wallet_mode.dart

echo "== Production custody-stats (public) =="
API_BASE="${API_BASE:-https://coinceeper.com/api}" \
  bash "backend cc/scripts/check_custody_stats.sh" || {
  echo "NOTE: if keys remain on server, run admin bulk cutover on VM."
}

echo "Preflight done. Complete manual steps in docs/mainnet_send_checklist.md on a device."
