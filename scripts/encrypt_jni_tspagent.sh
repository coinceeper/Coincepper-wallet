#!/usr/bin/env bash
# XOR ساده libtspagent.so → assets (هدر TSPF1) — جلوگیری از extract ساده از APK
#   export TSP_LIB_XOR_KEY=$(openssl rand -hex 32)
#   ./scripts/encrypt_jni_tspagent.sh <libtspagent.so> <out.dat>
#   مسیر نمونه داخل APK: android/app/src/main/assets/tspn/<abi>/libtspagent.dat
#   — یا به‌طور اتومات: TSP_TSPAGENT_TO_ASSETS=1 در scripts/build_gobridge.sh
set -euo pipefail
KEY="${TSP_LIB_XOR_KEY:-}"
if [[ -z "$KEY" || ${#KEY} -lt 32 ]]; then
  echo "error: set TSP_LIB_XOR_KEY to 64 hex chars" >&2
  exit 1
fi
if [[ "$#" -lt 2 ]]; then
  echo "usage: TSP_LIB_XOR_KEY=... $0 <libtspagent.so> <out.dat>" >&2
  exit 1
fi
IN="$1"
OUT="$2"
mkdir -p "$(dirname "$OUT")"
export TSP_LIB_XOR_KEY="$KEY"
export TSP_LIB_IN="$IN"
export TSP_LIB_OUT="$OUT"
python3 - <<'PY'
import os, sys
k = bytes.fromhex(os.environ["TSP_LIB_XOR_KEY"])
if len(k) < 16:
  sys.exit("key too short")
d = open(os.environ["TSP_LIB_IN"], "rb").read()
kb = (k * (len(d) // len(k) + 1))[: len(d)]
out = bytes(a ^ b for a, b in zip(d, kb))
open(os.environ["TSP_LIB_OUT"], "wb").write(b"TSPF1" + out)
print(len(d) + 5, "bytes ->", os.environ["TSP_LIB_OUT"])
PY
