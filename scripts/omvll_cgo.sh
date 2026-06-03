#!/usr/bin/env bash
# O-MVLL + agent mobilehost: فقط لایهٔ cgo (کد C تولیدشده و کامپایل cgo) می‌تواند با LLVM + O-MVLL پوشش داده شود.
# کامپایلر Go خودش LLVM نیست — برای خروجی LLVM از Go باید مسیر جدا (مثلاً TinyGo / زنجیرهٔ NCL) استفاده شود.
#
# منطق اصلی و متغیرهای محیطی در همان build_gobridge.sh است؛ این اسکریپت فقط:
#   - اختیاری: بارگذاری TSP_OMVLL_ENV_FILE
#   - سپس delegate به build_gobridge.sh
#
# مثال:
#   export TSP_OMVLL_CGO_CC="/path/to/omvll-wrapped-clang"
#   ./scripts/omvll_cgo.sh
#   # یا: export TSP_OMVLL_ENV_FILE="$HOME/omvll-cgo.env" && ./scripts/omvll_cgo.sh --android-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${TSP_OMVLL_ENV_FILE:-}" && -f "$TSP_OMVLL_ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$TSP_OMVLL_ENV_FILE"
  set +a
fi
exec "$ROOT/scripts/build_gobridge.sh" "$@"
