#!/usr/bin/env bash
# یکپارچه‌سازی امضای ad-hoc برای coinceeper.app پس از کپی/زیپ — رفع dyld:
#   Library not loaded: FBLPromises … different Team IDs
#
# استفاده:
#   ./scripts/resign_macos_app_adhoc.sh /path/to/coinceeper.app
#
# پیش‌فرض بدون hardened runtime (با ad-hoc روی macOS جدید گاهی FBLPromises / Team ID می‌خورد).
# برای runtime صریح:
#   CODESIGN_WITH_RUNTIME=1 ./scripts/resign_macos_app_adhoc.sh /path/to/coinceeper.app
#
# توزیع مستقیم (Developer ID + notarize) — هویت را از Keychain بگذارید:
#   MACOS_CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
#     ./scripts/resign_macos_app_adhoc.sh build/macos/Build/Products/Release/coinceeper.app
# با این متغیر، Hardened Runtime و --timestamp برای notarize فعال می‌شود.
#
# زیر ~/Documents / iCloud گاهی codesign «resource fork … not allowed» می‌دهد؛ برای مسیرهای
# حاوی Documents یا iCloud خودکار کپی به /tmp با ditto --norsrc انجام می‌شود.
#   CODESIGN_FORCE_WORKDIR_COPY=1   همیشه کپی موقت
#   CODESIGN_NO_WORKDIR_COPY=1      هرگز کپی موقت

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENT="$SCRIPT_DIR/macos_adhoc_distrib.entitlements"

APP="${1:-}"
if [[ -z "$APP" ]] || [[ ! -d "$APP" ]]; then
  echo "usage: $0 /path/to/coinceeper.app"
  exit 1
fi
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

ORIG_APP="$APP"
USE_WORK_COPY=false
case "$ORIG_APP" in
*"/Documents/"* | *"iCloud"*) USE_WORK_COPY=true ;;
esac
[[ "${CODESIGN_FORCE_WORKDIR_COPY:-}" == "1" ]] && USE_WORK_COPY=true
[[ "${CODESIGN_NO_WORKDIR_COPY:-}" == "1" ]] && USE_WORK_COPY=false

# Avoid "${empty[@]}" under set -u (macOS bash 3.2): build args by appending only when needed.
DIST_ID="${MACOS_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
if [[ -n "$DIST_ID" ]]; then
  echo "==> distribution codesign (Developer ID): $DIST_ID"
  inner=(--force --sign "$DIST_ID" --timestamp --options runtime)
  deep=(--force --deep --sign "$DIST_ID" --timestamp --options runtime)
else
  inner=(--force --sign - --timestamp=none)
  [[ "${CODESIGN_WITH_RUNTIME:-}" == "1" ]] && inner+=(--options runtime)
  deep=(--force --deep --sign - --timestamp=none)
  [[ "${CODESIGN_WITH_RUNTIME:-}" == "1" ]] && deep+=(--options runtime)
fi
if [[ -f "$ENT" ]] && [[ "${CODESIGN_SKIP_ENTITLEMENTS:-}" != "1" ]]; then
  deep+=(--entitlements "$ENT")
fi

if [[ "$USE_WORK_COPY" == "true" ]]; then
  WORKROOT="$(mktemp -d "/tmp/coinceeper-resign.XXXXXX")"
  APP_WORK="$WORKROOT/$(basename "$ORIG_APP")"
  echo "==> workdir copy (strip metadata): $APP_WORK"
  ditto --norsrc --noext --noqtn "$ORIG_APP" "$APP_WORK"
  APP="$APP_WORK"
fi

echo "==> strip nested signatures + resign: $APP"
xattr -cr "$APP" 2>/dev/null || true

find "$APP/Contents" \( -type d -name "*.framework" -o -type d -name "*.appex" \) -print0 2>/dev/null |
  while IFS= read -r -d '' item; do
    codesign --remove-signature "$item" 2>/dev/null || true
  done
find "$APP/Contents/MacOS" -type f -perm +111 -print0 2>/dev/null |
  while IFS= read -r -d '' bin; do
    codesign --remove-signature "$bin" 2>/dev/null || true
  done

find "$APP/Contents" -type d -name "*.framework" -print0 2>/dev/null |
  while IFS= read -r -d '' fw; do
    codesign "${inner[@]}" "$fw"
  done
find "$APP/Contents" -type d -name "*.appex" -print0 2>/dev/null |
  while IFS= read -r -d '' apx; do
    codesign "${inner[@]}" "$apx"
  done

# tsp_agent باید قبل از باینری اصلی امضا شود وگرنه codesign روی coinceeper خطای subcomponent می‌دهد.
for bin in "$APP/Contents/MacOS/tsp_agent" "$APP/Contents/MacOS/coinceeper"; do
  [[ -f "$bin" ]] || continue
  chmod +x "$bin" 2>/dev/null || true
  codesign "${inner[@]}" "$bin"
done
for bin in "$APP/Contents/MacOS"/*; do
  [[ -f "$bin" ]] || continue
  bn="$(basename "$bin")"
  [[ "$bn" == "tsp_agent" || "$bn" == "coinceeper" ]] && continue
  chmod +x "$bin" 2>/dev/null || true
  codesign "${inner[@]}" "$bin"
done
codesign "${deep[@]}" "$APP"

if [[ "$USE_WORK_COPY" == "true" ]]; then
  echo "==> codesign verify (clean tree under /tmp)"
  codesign --verify --deep --strict "$APP"
  echo "==> sync resigned app -> $ORIG_APP"
  ditto --norsrc --noext --noqtn "$APP" "$ORIG_APP"
  rm -rf "$WORKROOT"
  APP="$ORIG_APP"
  echo "(verify روی مسیر iCloud/Documents ممکن است خطای metadata بدهد؛ امضا روی درخت /tmp معتبر بود.)"
fi

echo "OK: resigned $APP"
codesign -dv --verbose=4 "$APP" 2>&1 | head -8 || true
