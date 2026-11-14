#!/bin/bash
set -euo pipefail
[ $# -eq 0 ] && set -- iphone ipad mac
targets=("$@")
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
work="$root/build/screenshots"
mkdir -p "$work" fastlane/screenshots/ios/en-US fastlane/screenshots/mac/en-US

simulator() {
  xcrun simctl list devices available -j | jq -r --arg pattern "$1" '[.devices[][] | select(.name | test($pattern))] | last | .udid'
}

run_ios() {
  local name="$1" pattern="$2" udid
  udid="$(simulator "$pattern")"
  [ -n "$udid" ] && [ "$udid" != "null" ] || { echo "No simulator matches $pattern" >&2; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  rm -rf "$work/$name"
  TEST_RUNNER_SCREENSHOT_DIR="$work/$name" xcodebuild test -project SignUtils.xcodeproj -scheme SignUtils \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/screenshots-dd \
    -only-testing:SignUtilsUITests/SignUtilsUITests/testScreenshots | xcbeautify
  for file in "$work/$name"/*.png; do
    cp "$file" "fastlane/screenshots/ios/en-US/${name}_$(basename "$file")"
  done
}

run_mac() {
  rm -rf "$work/mac"
  TEST_RUNNER_SCREENSHOT_DIR="$work/mac" xcodebuild test -project SignUtils.xcodeproj -scheme SignUtils \
    -destination "platform=macOS" -derivedDataPath build/screenshots-dd \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= \
    -only-testing:SignUtilsUITests/SignUtilsUITests/testScreenshots | xcbeautify
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
