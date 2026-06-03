#!/usr/bin/env bash
# انتقال پروژه از Documents/iCloud به External storage (بدون iCloud).
# قبل از اجرا در Finder: روی پوشه «flutter cc» → Download Now / Keep Downloaded on This Mac
set -euo pipefail

SRC="${1:-$HOME/Documents/coinceeper/flutter cc}"
DEST="/Volumes/External  storage/Projects/coinceeper/flutter-cc"

if [[ ! -d "/Volumes/External  storage" ]]; then
  echo "External storage وصل نیست." >&2
  exit 1
fi

if [[ ! -f "$SRC/pubspec.yaml" ]]; then
  echo "مسیر سورس درست نیست (pubspec.yaml نیست): $SRC" >&2
  exit 1
fi

mkdir -p "/Volumes/External  storage/Projects/coinceeper"
rm -rf "$DEST"

echo "کپی به $DEST (چند دقیقه طول می‌کشد)..."
rsync -a --partial \
  --exclude=.dart_tool/ \
  --exclude=build/ \
  --exclude=macos/Pods/ \
  --exclude=ios/Pods/ \
  --exclude=android/.gradle/ \
  --exclude=macos/Flutter/ephemeral/ \
  --exclude=ios/Flutter/ephemeral/ \
  --exclude=.tools/flutter/bin/cache/ \
  "$SRC/" "$DEST/"

echo "حذف پوشهٔ قدیمی در Documents (فقط بعد از کپی موفق)..."
rm -rf "$SRC"

ln -sf "$DEST" /tmp/coinceeper_flutter_cc

cd "$DEST"
./.tools/flutter/bin/flutter pub get
cd macos && pod install

cat <<EOF

✅ پروژه اینجاست:
   $DEST

Cursor/Xcode را از همین مسیر باز کنید.
Symlink: /tmp/coinceeper_flutter_cc → $DEST

EOF
