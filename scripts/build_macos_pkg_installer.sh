#!/usr/bin/env bash
# Build a standard Apple .pkg with Installer.app GUI (welcome/conclusion) that
# installs coinceeper.app into /Applications and runs postinstall (xattr + chmod).
#
# Usage:
#   bash scripts/build_macos_pkg_installer.sh SOURCE_APP OUT_PKG PKG_VERSION
# Example:
#   bash scripts/build_macos_pkg_installer.sh dist/coinceeper.app dist/out.pkg 1.0.38
#
# Optional: sign the installer for Gatekeeper (Developer ID Installer):
#   MACOS_INSTALLER_SIGN_IDENTITY='Developer ID Installer: Name (TEAMID)' \
#     bash scripts/build_macos_pkg_installer.sh dist/coinceeper.app dist/out.pkg 1.0.38

set -euo pipefail

SOURCE_APP="${1:?usage: $0 SOURCE_APP OUT_PKG PKG_VERSION}"
OUT_PKG="${2:?usage: $0 SOURCE_APP OUT_PKG PKG_VERSION}"
PKG_VER="${3:?usage: $0 SOURCE_APP OUT_PKG PKG_VERSION}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: pkgbuild/productbuild require macOS"
  exit 1
fi
for _c in pkgbuild productbuild ditto; do
  command -v "$_c" >/dev/null 2>&1 || {
    echo "error: missing command: $_c"
    exit 1
  }
done

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "error: SOURCE_APP not found: $SOURCE_APP"
  exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$HERE/mac_installer"
SCRIPTS_DIR="$RES/pkg_scripts"
chmod +x "$SCRIPTS_DIR/postinstall" 2>/dev/null || true

WORK="$(mktemp -d "/tmp/coinceeper-pkg.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto --norsrc --noext --noqtn "$SOURCE_APP" "$STAGE/coinceeper.app"

COMPONENT="$WORK/component.pkg"
pkgbuild \
  --root "$STAGE" \
  --identifier com.coinceeper.adl.pkg.app \
  --version "$PKG_VER" \
  --install-location /Applications \
  --scripts "$SCRIPTS_DIR" \
  "$COMPONENT"

DIST_XML="$WORK/distribution.xml"
sed "s|__PKG_VERSION__|${PKG_VER}|g" "$RES/distribution.xml.template" >"$DIST_XML"

mkdir -p "$(dirname "$OUT_PKG")"
rm -f "$OUT_PKG"
RAW_PKG="$WORK/product-unsigned.pkg"
productbuild \
  --distribution "$DIST_XML" \
  --resources "$RES/resources" \
  --package-path "$WORK" \
  "$RAW_PKG"

if [[ -n "${MACOS_INSTALLER_SIGN_IDENTITY:-}" ]]; then
  command -v productsign >/dev/null 2>&1 || {
    echo "error: productsign not found"
    exit 1
  }
  echo "==> productsign: $MACOS_INSTALLER_SIGN_IDENTITY"
  productsign --sign "$MACOS_INSTALLER_SIGN_IDENTITY" "$RAW_PKG" "$OUT_PKG"
else
  cp "$RAW_PKG" "$OUT_PKG"
fi

echo "OK: $OUT_PKG"
