#!/usr/bin/env bash
# 验证无签名或签名 Runner.app 的候选二进制边界；不替代 Archive Privacy Report。
set -euo pipefail

fail() {
  echo "bundle audit failed: $*" >&2
  exit 1
}

app_path="${1:-}"
[[ -n "$app_path" ]] || fail "usage: $0 /path/to/Runner.app"
[[ -d "$app_path" ]] || fail "Runner.app not found: $app_path"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$app_path/Info.plist"
assets_root="$app_path/Frameworks/App.framework/flutter_assets/packages/k478_practice/assets"
[[ -f "$info_plist" ]] || fail "Info.plist missing"
[[ -d "$assets_root" ]] || fail "Flutter candidate assets missing"

family0=$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:0' "$info_plist" 2>/dev/null) || fail "UIDeviceFamily missing"
[[ "$family0" == "1" ]] || fail "UIDeviceFamily[0] must be 1, got $family0"
if /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:1' "$info_plist" >/dev/null 2>&1; then
  fail "UIDeviceFamily must contain only iPhone (1)"
fi

for key in NSMicrophoneUsageDescription NSLocalNetworkUsageDescription NSBonjourServices; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$info_plist" >/dev/null 2>&1; then
    fail "unexpected privacy/network key: $key"
  fi
done

expected_frameworks=(
  App.framework
  Flutter.framework
  core_midi_input.framework
  flutter_midi_pro.framework
  objective_c.framework
)
for framework in "${expected_frameworks[@]}"; do
  [[ -d "$app_path/Frameworks/$framework" ]] || fail "expected framework missing: $framework"
done
while IFS= read -r framework; do
  name="$(basename "$framework")"
  case " ${expected_frameworks[*]} " in
    *" $name "*) ;;
    *) fail "unexpected native framework: $name" ;;
  esac
done < <(find "$app_path/Frameworks" -mindepth 1 -maxdepth 1 -type d -name '*.framework' -print)

for plugin in core_midi_input flutter_midi_pro; do
  privacy="$app_path/Frameworks/$plugin.framework/${plugin}_privacy.bundle/PrivacyInfo.xcprivacy"
  [[ -f "$privacy" ]] || fail "plugin privacy manifest missing: $privacy"
done

source_assets="$repo_root/packages/k478_practice/assets"
expected_relative_assets=(
  midi/mozart_k478_piano_quartet.mid
  soundfonts/k478_violin.sf2
  soundfonts/k478_cello.sf2
  legal/third_party_notices.txt
)
for page in $(seq -w 1 21); do
  expected_relative_assets+=(
    "scores/mozart_k478_piano_part/page-$page.png"
  )
done

is_expected_asset() {
  local candidate="$1"
  local expected
  for expected in "${expected_relative_assets[@]}"; do
    [[ "$candidate" == "$expected" ]] && return 0
  done
  return 1
}

# 只审计候选自定义资源子树；Flutter 运行时自己的 manifest、shader 等资产
# 位于外层 flutter_assets，不在这里判定。该子树的文件必须恰为已登记名单。
for relative in "${expected_relative_assets[@]}"; do
  [[ -f "$assets_root/$relative" ]] || fail "bundled asset missing: $relative"
  cmp -s "$source_assets/$relative" "$assets_root/$relative" || fail "bundled asset differs: $relative"
done
while IFS= read -r bundled_asset; do
  relative="${bundled_asset#"$assets_root/"}"
  is_expected_asset "$relative" || fail "unexpected candidate asset: $relative"
done < <(find "$assets_root" -mindepth 1 ! -type d -print)

page_count=$(find "$assets_root/scores/mozart_k478_piano_part" -maxdepth 1 -type f -name 'page-*.png' | wc -l | tr -d ' ')
[[ "$page_count" == "21" ]] || fail "expected exactly 21 bundled score pages, found $page_count"

[[ ! -e "$assets_root/scores/mozart_k478_piano_part.pdf" ]] || fail "raw PDF must not be bundled"
if find "$assets_root" -type f \( -iname '*timgm*' -o -iname '*.pdf' \) -print -quit | grep -q .; then
  fail "prohibited TimGM or PDF asset found"
fi
mid_count=$(find "$assets_root/midi" -type f -name '*.mid' | wc -l | tr -d ' ')
[[ "$mid_count" == "1" ]] || fail "expected exactly one bundled MIDI, found $mid_count"

echo "bundle audit passed: $app_path"
