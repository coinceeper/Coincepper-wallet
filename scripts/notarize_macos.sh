#!/usr/bin/env bash
# Submit a stapled-friendly artifact to Apple notary service, then staple.
#
# One-time setup (app-specific password in Keychain):
#   xcrun notarytool store-credentials "coinceeper-notary" \
#     --apple-id "you@example.com" --team-id TEAMID --password "@keychain:AC_PASSWORD"
#
# Usage:
#   NOTARY_KEYCHAIN_PROFILE=coinceeper-notary ./scripts/notarize_macos.sh /path/to/coinceeper.app
#   NOTARY_KEYCHAIN_PROFILE=coinceeper-notary ./scripts/notarize_macos.sh /path/to/Installer.pkg
#
# The bundle or package must already be signed with Developer ID (not ad-hoc).

set -euo pipefail

ARTIFACT="${1:?usage: $0 /path/to/coinceeper.app|.pkg|.dmg}"
PROFILE="${NOTARY_KEYCHAIN_PROFILE:?set NOTARY_KEYCHAIN_PROFILE (keychain profile name from notarytool store-credentials)}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: notarytool requires macOS"
  exit 1
fi

if [[ ! -e "$ARTIFACT" ]]; then
  echo "error: not found: $ARTIFACT"
  exit 1
fi

echo "==> notarytool submit --wait: $ARTIFACT"
xcrun notarytool submit "$ARTIFACT" --keychain-profile "$PROFILE" --wait
echo "==> stapler staple: $ARTIFACT"
xcrun stapler staple "$ARTIFACT"
echo "OK: notarized and stapled: $ARTIFACT"
