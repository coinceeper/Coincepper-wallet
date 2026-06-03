#!/usr/bin/env bash
# Hardened wrapper for libtspagent builds:
# - enables garble + external link flags
# - keeps O-MVLL cgo wrappers if set
# - optionally enables TinyGo experimental mode
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export TSP_HARDENED=1
export TSP_USE_GARBLE="${TSP_USE_GARBLE:-1}"
export TSP_GO_EXTLD="${TSP_GO_EXTLD:-1}"

if [[ "${TSP_USE_TINYGO:-0}" == "1" ]]; then
  export TSP_ALLOW_EXPERIMENTAL_TINYGO_CSHARED="${TSP_ALLOW_EXPERIMENTAL_TINYGO_CSHARED:-1}"
fi

exec "$ROOT/scripts/build_gobridge.sh" --hardened "$@"
