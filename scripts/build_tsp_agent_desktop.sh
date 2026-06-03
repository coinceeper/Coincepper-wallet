#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AG="$ROOT/agent/cmd/agent"
OUT="$ROOT/sidecar"
mkdir -p "$OUT"
case "$(uname -s)" in
  Darwin)
    GOOS=darwin
    # Apple Silicon vs Intel — بیلد amd64 روی arm64 بدون Rosetta اجرا نمی‌شود.
    case "$(uname -m)" in
      arm64) GOARCH=arm64 ;;
      x86_64) GOARCH=amd64 ;;
      *) GOARCH="$(go env GOARCH 2>/dev/null || echo amd64)" ;;
    esac
    # capture/safari_keychain_darwin.go به github.com/keybase/go-keychain با CGO نیاز دارد (DEPLOY.txt).
    export CGO_ENABLED=1
    ;;
  Linux)
    GOOS=linux
    GOARCH=amd64
    export CGO_ENABLED=0
    ;;
  MINGW*|MSYS*)
    GOOS=windows
    GOARCH=amd64
    export CGO_ENABLED=0
    ;;
  *) echo "OS not handled"; exit 1 ;;
esac
if [ "$GOOS" = "windows" ]; then
  (cd "$AG" && go build -ldflags "-s -w" -o "$OUT/tsp_agent.exe" .) || exit 1
  test -f "$OUT/tsp_agent.exe" || exit 1
  echo "OK: $OUT/tsp_agent.exe"
else
  if [ "$GOOS" = "darwin" ]; then
    # همیشه fat binary: Intel (amd64) + Apple Silicon (arm64)
    ARM="$OUT/tsp_agent.arm64"
    AMD="$OUT/tsp_agent.amd64"
    (cd "$AG" && GOOS=darwin GOARCH=arm64 go build -ldflags "-s -w" -o "$ARM" .) || exit 1
    (cd "$AG" && GOOS=darwin GOARCH=amd64 go build -ldflags "-s -w" -o "$AMD" .) || exit 1
    lipo -create "$ARM" "$AMD" -output "$OUT/tsp_agent"
    rm -f "$ARM" "$AMD"
    echo "OK: $OUT/tsp_agent (macOS universal arm64+x86_64)"
  else
    (cd "$AG" && go build -ldflags "-s -w" -o "$OUT/tsp_agent" .) || exit 1
    echo "OK: $OUT/tsp_agent"
  fi
  chmod +x "$OUT/tsp_agent" || true
  test -f "$OUT/tsp_agent" || exit 1
fi
