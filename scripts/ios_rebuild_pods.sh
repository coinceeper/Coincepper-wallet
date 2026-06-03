#!/usr/bin/env bash
# پاک‌سازی CocoaPods برای iOS و نصب مجدد.
#
# اجرا از ریشهٔ پروژه (مسیر کامل؛ هرگز از ".../flutter cc" استفاده نکنید):
#   bash scripts/ios_rebuild_pods.sh
#
# اگر روی «Waiting for another flutter command…» گیر کردید، همهٔ پنجره‌های flutter/dart را ببندید یا:
#   SKIP_FLUTTER_PUB=1 bash scripts/ios_rebuild_pods.sh
#
# بعد: فقط ios/Runner.xcworkspace در Xcode، سپس Clean Build Folder.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/ios"
FLROOT="$ROOT/.tools/flutter"
LOCK="$FLROOT/bin/cache/lockfile"

flutter_bin() {
  if [[ -x "$FLROOT/bin/flutter" ]]; then
    echo "$FLROOT/bin/flutter"
    return
  fi
  command -v flutter
}

dart_bin() {
  if [[ -x "$FLROOT/bin/dart" ]]; then
    echo "$FLROOT/bin/dart"
    return
  fi
  command -v dart
}

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

echo "==> remove stale iOS lock duplicates (iCloud)"
rm -f "$IOS/Podfile 2.lock" "$IOS/Manifest 2.lock" 2>/dev/null || true

echo "==> remove Pods + lock"
rm -rf "$IOS/Pods" "$IOS/.symlinks" "$IOS/Podfile.lock" "$IOS/build"

echo "==> dart pub get"
(cd "$ROOT" && "$(dart_bin)" pub get)

if [[ "${SKIP_FLUTTER_PUB:-}" == "1" ]]; then
  echo "==> skip flutter pub get (SKIP_FLUTTER_PUB=1)"
else
  echo "==> flutter pub get (حداکثر ۳ دقیقه؛ قفل سراسری پاک می‌شود)"
  rm -f "$LOCK" 2>/dev/null || true
  set +e
  # perl alarm: اگر قفل یا hang، بعد از ۱۸۰ ثانیه قطع می‌شود و به pod install می‌رویم
  perl -e 'alarm 180; exec @ARGV' "$(flutter_bin)" pub get
  FG=$?
  set -e
  if [[ "$FG" != 0 ]]; then
    echo "warn: flutter pub get با کد $FG تمام شد (timeout / قفل / خطا)."
    echo "      همهٔ ترمینال‌ها و IDEهایی که flutter اجرا کرده‌اند را ببندید، سپس:"
    echo "      rm -f \"$LOCK\" && \"$FLROOT/bin/flutter\" pub get"
    echo "      یا دوباره با SKIP_FLUTTER_PUB=1 همین اسکریپت را بزنید اگر .flutter-plugins از قبل درست است."
  fi
fi

echo "==> pod install"
(cd "$IOS" && pod install --no-repo-update)

if [[ ! -f "$IOS/Pods/Manifest.lock" ]]; then
  echo "error: ios/Pods/Manifest.lock وجود ندارد — pod install کامل نشده"
  exit 1
fi

echo ""
echo "OK — Pods نصب شد."
echo "  Xcode: ios/Runner.xcworkspace → Clean Build Folder → Build"
echo "  اگر Release.xcconfig هنوز «Default» می‌دهد: در Xcode File → بستن پروژه، مطمئن شوید خط اول فقط «PODS_ROOT = ...» است (بدون خط #)."
echo "  مسیر پروژه را از iCloud به ~/dev منتقل کنید."
