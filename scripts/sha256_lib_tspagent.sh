#!/usr/bin/env bash
# SHA-256 فایل libtspagent.so — برای [opsec.lib_integrity_sha256] / AGENT_LIB_INTEGRITY_SHA256
#   ./scripts/sha256_lib_tspagent.sh android/app/src/main/jniLibs/arm64-v8a/libtspagent.so
set -euo pipefail
f="${1:?usage: $0 <libtspagent.so>}"
shasum -a 256 "$f" | awk '{print $1}'
