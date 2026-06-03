#!/usr/bin/env bash
# بستهٔ قابل انتقال macOS: coinceeper.app + tsp_agent + ZIP در dist/
# هدف: Apple Silicon (arm64) و Intel (x86_64) — اپ Release و tsp_agent هر دو universal.
#
# اجرا از ریشهٔ پروژه:
#   ./scripts/package_macos_distribution.sh
#
# اگر پروژه زیر iCloud/Documents است و CodeSign با «resource fork» می‌خورد:
#   MACOS_DIST_TMP=1 ./scripts/package_macos_distribution.sh
#   (بعد از موفقیت، همان .app امضا‌شده به build/.../Release و dist/coinceeper.app در ریشهٔ پروژه کپی می‌شود.)
#
# Flutter: PATH یا FLUTTER_BIN یا .tools/flutter در ریشه
#
# توزیع غیررسمی (پیش‌فرض): امضای ad-hoc (--sign -). روی مک دیگر اولین بار: کلیک راست → Open.
#
# توزیع مستقیم رسمی (Developer ID + notarize):
#   export MACOS_CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
#   xcrun notarytool store-credentials "coinceeper-notary" --apple-id ... --team-id ... --password "@keychain:..."
#   export NOTARY_KEYCHAIN_PROFILE=coinceeper-notary
#   export MACOS_NOTARIZE=1
#   اختیاری برای .pkg امضا + notarize نصب‌کننده:
#   export MACOS_INSTALLER_SIGN_IDENTITY='Developer ID Installer: Your Name (TEAMID)'
#   export MACOS_NOTARIZE_PKG=1
#   ./scripts/package_macos_distribution.sh

set -euo pipefail

ORIG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$ORIG_ROOT"

if [[ "${MACOS_NOTARIZE:-}" == "1" ]]; then
  if [[ -z "${MACOS_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}" ]]; then
    echo "error: MACOS_NOTARIZE=1 requires MACOS_CODESIGN_IDENTITY (Developer ID Application …)"
    exit 1
  fi
  if [[ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "error: MACOS_NOTARIZE=1 requires NOTARY_KEYCHAIN_PROFILE"
    exit 1
  fi
fi
if [[ "${MACOS_NOTARIZE_PKG:-}" == "1" ]]; then
  if [[ -z "${MACOS_INSTALLER_SIGN_IDENTITY:-}" ]]; then
    echo "error: MACOS_NOTARIZE_PKG=1 requires MACOS_INSTALLER_SIGN_IDENTITY (Developer ID Installer …)"
    exit 1
  fi
  if [[ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "error: MACOS_NOTARIZE_PKG=1 requires NOTARY_KEYCHAIN_PROFILE"
    exit 1
  fi
fi

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
  echo "error: flutter not found — install Flutter, or clone to .tools/flutter, or set FLUTTER_BIN="
  exit 1
}

if [[ "${MACOS_DIST_TMP:-}" == "1" ]]; then
  TMP="$(mktemp -d "/tmp/coinceeper-dist.XXXXXX")"
  cleanup() { rm -rf "$TMP"; }
  trap cleanup EXIT
  echo "==> MACOS_DIST_TMP: rsync lean tree -> $TMP/w (no build/.dart_tool/.git; avoids filling /tmp)"
  mkdir -p "$TMP/w"
  rsync -a \
    --exclude 'build/' \
    --exclude '.dart_tool/' \
    --exclude '.git/' \
    --exclude 'android/.gradle/' \
    --exclude 'android/app/build/' \
    --exclude 'android/build/' \
    --exclude 'ios/Pods/' \
    --exclude 'ios/build/' \
    --exclude '.tools/flutter/' \
    --exclude '**/node_modules/' \
    --exclude '**/DerivedData/' \
    "$ORIG_ROOT/" "$TMP/w/"
  ROOT="$TMP/w"
  cd "$ROOT"
  mkdir -p "$ROOT/.tools"
  if [[ -d "$ORIG_ROOT/.tools/flutter" ]]; then
    ln -sf "$ORIG_ROOT/.tools/flutter" "$ROOT/.tools/flutter"
  fi
fi

export PATH="$(dirname "$FL"):$PATH"

cd "$ROOT"
bash "$ROOT/scripts/build_tsp_agent_desktop.sh"

xattr -cr macos assets 2>/dev/null || true
"$FL" pub get
"$FL" build macos --release

APP="$ROOT/build/macos/Build/Products/Release/coinceeper.app"
if [[ ! -d "$APP" ]]; then
  echo "error: missing $APP"
  exit 1
fi

cp "$ROOT/sidecar/tsp_agent" "$APP/Contents/MacOS/tsp_agent"
chmod +x "$APP/Contents/MacOS/tsp_agent"
echo "==> binaries (expect universal arm64+x86_64 for distribution)"
file "$APP/Contents/MacOS/coinceeper" "$APP/Contents/MacOS/tsp_agent" || true
bash "$ORIG_ROOT/scripts/resign_macos_app_adhoc.sh" "$APP"

LOCAL_RELEASE_APP="$ORIG_ROOT/build/macos/Build/Products/Release/coinceeper.app"
if [[ -d "$APP" ]]; then
  echo "==> sync signed .app -> project Release path + dist/ (برای open از Documents، نه فقط زیپ)"
  mkdir -p "$(dirname "$LOCAL_RELEASE_APP")"
  rm -rf "$LOCAL_RELEASE_APP"
  ditto --norsrc --noext --noqtn "$APP" "$LOCAL_RELEASE_APP"
  mkdir -p "$ORIG_ROOT/dist"
  rm -rf "$ORIG_ROOT/dist/coinceeper.app"
  ditto --norsrc --noext --noqtn "$APP" "$ORIG_ROOT/dist/coinceeper.app"
fi

DIST_APP="$ORIG_ROOT/dist/coinceeper.app"
if [[ "${MACOS_NOTARIZE:-}" == "1" ]] && [[ -d "$DIST_APP" ]]; then
  echo ""
  echo "==> notarize + staple (dist .app)"
  bash "$ORIG_ROOT/scripts/notarize_macos.sh" "$DIST_APP"
  if [[ -d "$(dirname "$LOCAL_RELEASE_APP")" ]]; then
    echo "==> sync stapled .app -> $LOCAL_RELEASE_APP"
    rm -rf "$LOCAL_RELEASE_APP"
    ditto --norsrc --noext --noqtn "$DIST_APP" "$LOCAL_RELEASE_APP"
  fi
fi

if command -v spctl >/dev/null 2>&1; then
  echo ""
  if [[ -n "${MACOS_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}" ]]; then
    echo "==> spctl (با Developer ID؛ پس از notarize معمولاً accepted):"
  else
    echo "==> spctl (با امضای ad-hoc معمولاً rejected است؛ برای کاربر: باز کردن با کلیک راست → Open):"
  fi
  SPCTL_T="$APP"
  [[ -d "$DIST_APP" ]] && SPCTL_T="$DIST_APP"
  spctl --assess --verbose=4 "$SPCTL_T" 2>&1 || true
fi

VER="$(grep '^version:' "$ORIG_ROOT/pubspec.yaml" | head -1 | cut -d: -f2- | xargs)"
VER_FILE="${VER//+/_}"

DIST="$ORIG_ROOT/dist"
mkdir -p "$DIST"
ZIP_REL="coinceeper-macos-${VER_FILE}.zip"
ZIP="$DIST/$ZIP_REL"
rm -f "$ZIP"

# ZIP از dist اگر موجود (مثلاً بعد از staple) تا باندل دقیقاً همان چیزی باشد که notarize شده.
ZIP_SRC="$APP"
[[ -d "$DIST_APP" ]] && ZIP_SRC="$DIST_APP"
# ZIP از نسخهٔ بدون متای حجیم ساخته می‌شود تا بازکردن از زیپ روی مک دیگر با dyld/codesign بهتر باشد.
ZIP_STAGE="$(mktemp -d "/tmp/coinceeper-zipstage.XXXXXX")"
ditto --norsrc --noext --noqtn "$ZIP_SRC" "$ZIP_STAGE/coinceeper.app" || {
  rm -rf "$ZIP_STAGE"
  exit 1
}
(
  cd "$ZIP_STAGE"
  # بدون sequesterRsrc تا پوشهٔ __MACOSX و ._ داخل زیپ نرود (بازکردن روی مک‌های دیگر تمیزتر است).
  ditto -c -k --keepParent --norsrc --noext --noqtn --zlibCompressionLevel 6 "coinceeper.app" "$ZIP"
) || {
  rm -rf "$ZIP_STAGE"
  exit 1
}
rm -rf "$ZIP_STAGE"

_SZ="$(du -sh "$ZIP" | awk '{print $1}')"
echo "OK: $ZIP ($_SZ)"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

PKG_VER="${VER%%+*}"
PKG_REL="coinceeper-macos-${VER_FILE}.pkg"
PKG="$DIST/$PKG_REL"
rm -f "$PKG" "${PKG}.sha256"
bash "$ORIG_ROOT/scripts/build_macos_pkg_installer.sh" "$ORIG_ROOT/dist/coinceeper.app" "$PKG" "$PKG_VER"
_PKG_SZ="$(du -sh "$PKG" | awk '{print $1}')"
echo "OK: $PKG ($_PKG_SZ)"
shasum -a 256 "$PKG" | tee "${PKG}.sha256"

if [[ "${MACOS_NOTARIZE_PKG:-}" == "1" ]] && [[ -f "$PKG" ]]; then
  echo ""
  echo "==> notarize + staple (.pkg)"
  bash "$ORIG_ROOT/scripts/notarize_macos.sh" "$PKG"
fi

echo ""
echo "نصب روی مک:"
echo "  • پکیج با UI (Installer): فایل .pkg را باز کنید و مراحل را دنبال کنید — اپ در Applications نصب می‌شود؛ پس از نصب، اسکریپت postinstall معادل xattr -dr quarantine و chmod +x روی باندل را اجرا می‌کند."
echo "  • یا زیپ: باز کنید و coinceeper.app را به Applications بکشید."
echo "اپ موقع بالا آمدن (در هر دو حالت) هم می‌تواند همان پاک‌سازی quarantine را روی باندل تکمیل کند."
echo "اولین اجرا از اینترنت: اگر Gatekeeper مسدود کرد، یک بار کلیک راست → Open (یا Developer ID + notarize)."
echo "سایدکار tsp_agent کنار coinceeper در همان .app است (Release بدون App Sandbox برای spawn ایجنت)."
echo "check‑in ops: متغیرهای AGENT_* از اپ به فرآیند ایجنت پاس داده می‌شوند؛ در Console/ترمینال خط tsp_agent stderr را ببینید."
echo ""
echo "مسیرهای همسان با زیپ/پکیج (برای تست open ، از Trash یا بیلد قدیمی Documents استفاده نکنید):"
echo "  $ORIG_ROOT/dist/coinceeper.app"
echo "  $LOCAL_RELEASE_APP"
