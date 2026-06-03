#!/usr/bin/env bash
# بعد از تغییر version در pubspec.yaml، Xcode گاهی هنوز FLUTTER_BUILD_NAME قدیمی را از
# macos/Flutter/ephemeral/ می‌خواند چون flutter pub get فایل را عوض نمی‌کند.
# این اسکریپت فایل‌های تولیدشدهٔ نسخه را حذف می‌کند و pub get دوباره آن‌ها را از pubspec می‌سازد.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FL="${FLUTTER_BIN:-$ROOT/.tools/flutter/bin/flutter}"
if [[ ! -x "$FL" ]]; then FL="$(command -v flutter)"; fi
[[ -x "$FL" ]] || { echo "error: flutter not found"; exit 1; }
rm -f \
  "$ROOT/macos/Flutter/ephemeral/Flutter-Generated.xcconfig" \
  "$ROOT/macos/Flutter/ephemeral/flutter_export_environment.sh" \
  "$ROOT/ios/Flutter/Generated.xcconfig" \
  "$ROOT/ios/Flutter/flutter_export_environment.sh"
"$FL" pub get
echo "OK: FLUTTER_BUILD from pubspec — macOS:"
grep -E '^FLUTTER_BUILD_(NAME|NUMBER)=' "$ROOT/macos/Flutter/ephemeral/Flutter-Generated.xcconfig" 2>/dev/null || echo "(macOS ephemeral missing — run flutter build macos once)"
