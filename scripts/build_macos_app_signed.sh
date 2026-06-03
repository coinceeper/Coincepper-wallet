#!/usr/bin/env bash
# بیلد Release macOS + tsp_agent + امضای باندل با Hardened Runtime (مثل دستور دستی شما).
#
# از ریشهٔ پروژه:
#   ./scripts/build_macos_app_signed.sh
#
# بدون flutter clean (سریع‌تر برای تکرار):
#   NO_FLUTTER_CLEAN=1 ./scripts/build_macos_app_signed.sh
#
# اگر پروژه زیر Documents/iCloud است و CodeSign خطای resource fork می‌دهد:
#   MACOS_DIST_TMP=1 ./scripts/build_macos_app_signed.sh
#
# خروجی: build/macos/Build/Products/Release/coinceeper.app
#
# نکتهٔ spctl: با امضای ad-hoc (--sign -) معمولاً «rejected» می‌گیرید؛ برای توزیع واقعی
# نیاز به Apple Developer + Developer ID + notarize است.

set -euo pipefail

ORIG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${BUILD_ROOT:-$ORIG_ROOT}"

flutter_bin() {
  if [[ -n "${FLUTTER_BIN:-}" ]] && [[ -x "${FLUTTER_BIN}" ]]; then
    echo "$FLUTTER_BIN"
    return
  fi
  if [[ -x "$ORIG_ROOT/.tools/flutter/bin/flutter" ]]; then
    echo "$ORIG_ROOT/.tools/flutter/bin/flutter"
    return
  fi
  command -v flutter
}

FL="$(flutter_bin)" || {
  echo "error: flutter not found — PATH یا FLUTTER_BIN یا .tools/flutter"
  exit 1
}
export PATH="$(dirname "$FL"):$PATH"

# فقط وقتی خودتان MACOS_DIST_TMP=1 می‌زنید و BUILD_ROOT ست نشده (پکیج ZIP خودش TMP می‌سازد و BUILD_ROOT می‌دهد)
if [[ "${MACOS_DIST_TMP:-}" == "1" ]] && [[ -z "${BUILD_ROOT:-}" ]]; then
  TMP="$(mktemp -d "/tmp/coinceeper-build.XXXXXX")"
  cleanup() { rm -rf "$TMP"; }
  trap cleanup EXIT
  echo "==> MACOS_DIST_TMP: rsync project -> $TMP/w (exclude build/.dart_tool/Pods to avoid iCloud/timeouts)"
  mkdir -p "$TMP/w"
  rsync -a \
    --exclude='build/' \
    --exclude='.dart_tool/' \
    --exclude='ios/Pods/' \
    --exclude='ios/.symlinks/' \
    --exclude='macos/Pods/' \
    --exclude='macos/.symlinks/' \
    --exclude='.git/' \
    "$ORIG_ROOT/" "$TMP/w/"
  ROOT="$TMP/w"
  mkdir -p "$ROOT/.tools"
  [[ -d "$ORIG_ROOT/.tools/flutter" ]] && ln -sf "$ORIG_ROOT/.tools/flutter" "$ROOT/.tools/flutter"
fi

cd "$ROOT"

if [[ "${NO_FLUTTER_CLEAN:-}" != "1" ]]; then
  echo "==> flutter clean"
  "$FL" clean
fi

echo "==> flutter pub get"
"$FL" pub get

echo "==> build tsp_agent sidecar"
bash "$ROOT/scripts/build_tsp_agent_desktop.sh"

xattr -cr macos assets 2>/dev/null || true

echo "==> flutter build macos --release"
"$FL" build macos --release

REL="$ROOT/build/macos/Build/Products/Release"
APP="$REL/coinceeper.app"
if [[ ! -d "$APP" ]]; then
  echo "error: missing $APP"
  exit 1
fi

echo "==> bundle tsp_agent into .app"
cp "$ROOT/sidecar/tsp_agent" "$APP/Contents/MacOS/tsp_agent"
chmod +x "$APP/Contents/MacOS/tsp_agent"
xattr -cr "$APP" 2>/dev/null || true

# یک `codesign --deep` روی کل .app کافی نیست: فریمورک‌های CocoaPods (مثل FBLPromises) اغلب با Team ID
# بیلد Xcode می‌مانند و باینری اصلی ad-hoc می‌شود → dyld: «different Team IDs».
# اسکریپت زیر امضای تو در تو را حذف و همهٔ framework/باینری را با همان هویت یکدست می‌کند.
echo "==> uniform ad-hoc resign (Firebase / Promises frameworks + main binary)"
bash "$ROOT/scripts/resign_macos_app_adhoc.sh" "$APP"

echo "==> codesign verify"
codesign --verify --deep --strict "$APP" 2>/dev/null || codesign --verify --verbose=4 "$APP" || true

# بیلد داخل /tmp بوده؛ قبل از trap پاک‌کننده، خروجی را به ریشهٔ واقعی پروژه برگردانیم.
if [[ "$ROOT" != "$ORIG_ROOT" ]] && [[ -d "$APP" ]]; then
  echo "==> sync built .app -> $ORIG_ROOT/dist/ and $ORIG_ROOT/build/macos/.../Release/"
  mkdir -p "$ORIG_ROOT/dist"
  rm -rf "$ORIG_ROOT/dist/coinceeper.app"
  ditto --norsrc --noext --noqtn "$APP" "$ORIG_ROOT/dist/coinceeper.app"
  mkdir -p "$ORIG_ROOT/build/macos/Build/Products/Release"
  rm -rf "$ORIG_ROOT/build/macos/Build/Products/Release/coinceeper.app"
  ditto --norsrc --noext --noqtn "$APP" "$ORIG_ROOT/build/macos/Build/Products/Release/coinceeper.app"
  # حذف quarantine/metadata تا دابل‌کلیک «can't be opened» به‌خاطر Gatekeeper کمتر شود
  xattr -cr "$ORIG_ROOT/dist/coinceeper.app" 2>/dev/null || true
  xattr -cr "$ORIG_ROOT/build/macos/Build/Products/Release/coinceeper.app" 2>/dev/null || true
fi

echo "==> spctl --assess (ad-hoc اغلب rejected — طبیعی است)"
set +e
spctl --assess --verbose=4 "$APP"
SC=$?
set -e
if [[ "$SC" != 0 ]]; then
  echo "spctl exit $SC (برای توزیع خارج از Mac خودتان معمولاً نیاز به Developer ID + notarize است)"
fi

echo ""
echo "OK: $APP"
