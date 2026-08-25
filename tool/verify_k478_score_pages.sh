#!/usr/bin/env bash
# 从已核验的 K.478 PDF 复现 21 张随包页面图；临时目录在退出时自动清理。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_pdf="$repo_root/packages/k478_practice/assets/scores/mozart_k478_piano_part.pdf"
page_dir="$repo_root/packages/k478_practice/assets/scores/mozart_k478_piano_part"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/k478-score-pages.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

renderer="${PDFTOPPM_BIN:-}"
if [[ -z "$renderer" ]]; then
  renderer="$(command -v pdftoppm || true)"
fi
[[ -n "$renderer" && -x "$renderer" ]] || {
  echo "pdftoppm is required (Poppler 26.05.0 was verified)" >&2
  echo "set PDFTOPPM_BIN to a task-specific renderer path when it is not on PATH" >&2
  exit 1
}
[[ -f "$source_pdf" ]] || { echo "source PDF missing: $source_pdf" >&2; exit 1; }

"$renderer" -r 180 -png "$source_pdf" "$tmp_dir/page"
for page in $(seq -w 1 21); do
  rendered="$tmp_dir/page-$page.png"
  # 不同 Poppler 版本可能使用一位或两位页码。
  [[ -f "$rendered" ]] || rendered="$tmp_dir/page-${page#0}.png"
  [[ -f "$rendered" ]] || { echo "rendered page missing: $rendered" >&2; exit 1; }
  cmp -s "$rendered" "$page_dir/page-$page.png" || {
    echo "score page differs: page-$page.png" >&2
    exit 1
  }
done
extra_pages=$(find "$tmp_dir" -maxdepth 1 -type f -name 'page-*.png' | wc -l | tr -d ' ')
[[ "$extra_pages" == "21" ]] || { echo "expected 21 rendered pages, got $extra_pages" >&2; exit 1; }

echo "K.478 score pages verified with $($renderer -v 2>&1 | head -1)"
