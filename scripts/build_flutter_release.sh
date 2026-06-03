#!/usr/bin/env bash
# لایه ۱: مبهم‌سازی Dart/Flutter (release) — نمادها و stack trace نگاشت جدا.
# این اسکریپت برای iOS و Android یکسان است:
#   - iOS: flutter build ios|ipa  با --obfuscate (لایه Dart/Flutter)
#   - agent Go (xstr و غیر): همان باینری/آرشیو در build_gobridge.sh --ios-only به xcframework
#     لینک می‌شود؛ R8/ProGuard فقط اندروید است (جاوا/کاتلین) و معادل آن در iOS
#     تنظیمات Xcode/Archive (strip, dSYM جدا) است.
# اجرا از ریشهٔ پروژه Flutter:
#   ./scripts/build_flutter_release.sh
#   ./scripts/build_flutter_release.sh apk|appbundle|ios|ipa
# خروجی نقشهٔ نمادها: build/split-debug-info/ (با گیت نکنید مگر سیاستتان اجازه دهد)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v flutter >/dev/null 2>&1 || { echo "error: flutter not in PATH"; exit 1; }

SPLIT_DIR="${FLUTTER_SPLIT_DEBUG_INFO:-$ROOT/build/split-debug-info}"
mkdir -p "$SPLIT_DIR"
TARGET="${1:-apk}"
case "$TARGET" in
  apk|appbundle|ios|ipa) ;;
  *) echo "usage: $0 [apk|appbundle|ios|ipa]"; exit 1 ;;
esac

echo "==> flutter build $TARGET (obfuscate, split-debug-info -> $SPLIT_DIR)"
exec flutter build "$TARGET" --obfuscate --split-debug-info="$SPLIT_DIR" --release
