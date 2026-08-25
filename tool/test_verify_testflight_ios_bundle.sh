#!/usr/bin/env bash
# 为 Runner.app 资产白名单做独立回归测试；仅构造临时最小 bundle。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
audit="$repo_root/tool/verify_testflight_ios_bundle.sh"
source_assets="$repo_root/packages/k478_practice/assets"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/k478-bundle-audit.XXXXXX")"
app_path="$temp_root/Runner.app"
flutter_assets_root="$app_path/Frameworks/App.framework/flutter_assets"
assets_root="$app_path/Frameworks/App.framework/flutter_assets/packages/k478_practice/assets"
font_manifest="$flutter_assets_root/FontManifest.json"
cupertino_font="$flutter_assets_root/packages/cupertino_icons/assets/CupertinoIcons.ttf"

cleanup() {
  rm -rf "$temp_root"
}
trap cleanup EXIT

mkdir -p "$app_path/Frameworks"
cat > "$app_path/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>UIDeviceFamily</key><array><integer>1</integer></array></dict></plist>
PLIST

for framework in App Flutter core_midi_input flutter_midi_pro objective_c; do
  mkdir -p "$app_path/Frameworks/$framework.framework"
done
for plugin in core_midi_input flutter_midi_pro; do
  privacy="$app_path/Frameworks/$plugin.framework/${plugin}_privacy.bundle/PrivacyInfo.xcprivacy"
  mkdir -p "$(dirname "$privacy")"
  : > "$privacy"
done

mkdir -p "$(dirname "$assets_root")"
cp -R "$source_assets" "$assets_root"
rm -f \
  "$assets_root/scores/mozart_k478_piano_part.pdf" \
  "$assets_root/soundfonts/README.md"
mkdir -p "$(dirname "$cupertino_font")"
: > "$cupertino_font"
printf '[{"family":"packages/cupertino_icons/CupertinoIcons","fonts":[{"asset":"packages/cupertino_icons/assets/CupertinoIcons.ttf"}]}]\n' > "$font_manifest"

"$audit" "$app_path" >/dev/null

expect_rejected() {
  local label="$1"
  if "$audit" "$app_path" >/dev/null 2>&1; then
    echo "bundle audit self-test failed: did not reject $label" >&2
    exit 1
  fi
}

printf 'not allowed' > "$assets_root/soundfonts/extra.sf2"
expect_rejected 'extra SoundFont'
rm -f "$assets_root/soundfonts/extra.sf2"

printf 'not allowed' > "$assets_root/unregistered.bin"
expect_rejected 'arbitrary custom asset'
rm -f "$assets_root/unregistered.bin"

mkdir -p "$flutter_assets_root/assets"
printf 'not allowed' > "$flutter_assets_root/assets/unregistered.bin"
expect_rejected 'host-level Flutter asset'
rm -rf "$flutter_assets_root/assets"

mkdir -p "$flutter_assets_root/packages/unregistered_package"
printf 'not allowed' > "$flutter_assets_root/packages/unregistered_package/asset.bin"
expect_rejected 'unregistered package asset'

echo 'bundle audit allowlist self-test passed'
