#!/usr/bin/env bash
# تأیید کامندلاین: agent/cmd/mobilehost برای هاست (و در صورت وجود NDK، یک ABI اندروید)
# حالت سخت‌سازی: TSP_VERIFY_HARDENED=1  →  بررسی وجود garble و tinygo (در صورت درخواست)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT="$ROOT/agent"
cd "$AGENT"
echo "==> go build (host, CGO) ./cmd/mobilehost"
export CGO_ENABLED=1
go build -o /tmp/tspagent_host_check ./cmd/mobilehost
rm -f /tmp/tspagent_host_check
echo "  OK: agent/cmd/mobilehost compiles (host)."

if [[ "${TSP_VERIFY_HARDENED:-0}" == "1" ]]; then
  command -v garble >/dev/null 2>&1 || { echo "error: garble missing for hardened verify"; exit 1; }
  if [[ "${TSP_USE_TINYGO:-0}" == "1" ]]; then
    command -v tinygo >/dev/null 2>&1 || { echo "error: tinygo missing while TSP_USE_TINYGO=1"; exit 1; }
  fi
  echo "  OK: hardened toolchain requirements present."
fi

if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt" ]]; then
  PB="$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -maxdepth 1 -mindepth 1 -type d | head -1)"
  CC="$PB/bin/aarch64-linux-android26-clang"
  if [[ -x "$CC" ]]; then
    echo "==> go build GOOS=android GOARCH=arm64 (sample)"
    CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$CC" \
      go build -o /dev/null ./cmd/mobilehost
    echo "  OK: mobilehost برای arm64-android."
  else
    echo "  (skip) no aarch64-linux-android26-clang"
  fi
else
  echo "  (skip) set ANDROID_NDK_HOME for android cross-check"
fi
echo "برای iOS: bash scripts/build_gobridge.sh --ios-only  (مک + Xcode + Go)"
echo "Done."
