#!/bin/bash
set -euo pipefail
[ $# -eq 0 ] && set -- iphone ipad mac
targets=("$@")
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
work="$root/build/screenshots"
mkdir -p "$work" fastlane/screenshots/ios/en-US fastlane/screenshots/mac/en-US

extract() {
  local result="$1" destination="$2"
  rm -rf "$destination" "$destination.attachments"
  mkdir -p "$destination"
  xcrun xcresulttool export attachments --path "$result" --output-path "$destination.attachments" >/dev/null
  python3 - "$destination.attachments" "$destination" <<'PY2'
import json, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
for test in json.load(open(f"{source}/manifest.json")):
    for attachment in test["attachments"]:
        match = re.match(r"(\d\d_[a-z_]+)_\d+_", attachment["suggestedHumanReadableName"])
        if match and attachment["exportedFileName"].endswith(".png"):
            shutil.copy(f"{source}/{attachment['exportedFileName']}", f"{target}/{match.group(1)}.png")
PY2
  rm -rf "$destination.attachments"
}

simulator() {
  xcrun simctl list devices available -j | jq -r --arg pattern "$1" '[.devices[][] | select(.name | test($pattern))] | last | .udid'
}

run_ios() {
  local name="$1" pattern="$2" udid
  udid="$(simulator "$pattern")"
  [ -n "$udid" ] && [ "$udid" != "null" ] || { echo "No simulator matches $pattern" >&2; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance dark
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  rm -rf "$work/$name.xcresult"
  xcodebuild test -project SignUtils.xcodeproj -scheme SignUtils \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/screenshots-dd \
    -resultBundlePath "$work/$name.xcresult" \
    -only-testing:SignUtilsUITests/SignUtilsUITests/testScreenshots | xcbeautify
  extract "$work/$name.xcresult" "$work/$name"
  for file in "$work/$name"/*.png; do
    cp "$file" "fastlane/screenshots/ios/en-US/${name}_$(basename "$file")"
  done
}

run_mac() {
  rm -rf "$work/mac.xcresult"
  xcodebuild test -project SignUtils.xcodeproj -scheme SignUtils \
    -destination "platform=macOS" -derivedDataPath build/screenshots-dd \
    -resultBundlePath "$work/mac.xcresult" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= \
    -only-testing:SignUtilsUITests/SignUtilsUITests/testScreenshots | xcbeautify
  extract "$work/mac.xcresult" "$work/mac"
  for file in "$work/mac"/*.png; do
    swift scripts/compose-mac-screenshot.swift "$file" "fastlane/screenshots/mac/en-US/$(basename "$file")"
  done
}

for target in "${targets[@]}"; do
  case "$target" in
    iphone) run_ios iphone '^iPhone [0-9]+ Pro Max$' ;;
    ipad) run_ios ipad '^iPad Pro 13-inch' ;;
    mac) run_mac ;;
    *) echo "Unknown target $target" >&2; exit 64 ;;
  esac
done
