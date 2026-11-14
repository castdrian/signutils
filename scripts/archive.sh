#!/bin/bash
set -euo pipefail
platform="$1"
mode="${2:-upload}"
case "$platform" in
  ios) destination="generic/platform=iOS" ;;
  macos) destination="generic/platform=macOS" ;;
  *) echo "usage: archive.sh ios|macos [upload|export]" >&2; exit 64 ;;
esac
: "${APP_STORE_CONNECT_KEY_ID:?}" "${APP_STORE_CONNECT_ISSUER_ID:?}" "${APP_STORE_CONNECT_PRIVATE_KEY_BASE64:?}"
key_dir="$(mktemp -d)"
key="$key_dir/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
trap 'rm -rf "$key_dir"' EXIT
echo "$APP_STORE_CONNECT_PRIVATE_KEY_BASE64" | base64 --decode > "$key"
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key" -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")
archive="build/SignUtils-$platform.xcarchive"
xcodebuild archive \
  -project SignUtils.xcodeproj \
  -scheme SignUtils \
  -configuration Release \
  -destination "$destination" \
  -archivePath "$archive" \
  -derivedDataPath build/archive-dd \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  PROVISIONING_PROFILE_SPECIFIER= \
  DEVELOPMENT_TEAM=L988J7YMK5 | xcbeautify
options=ExportOptions-AppStore.plist
if [ "$mode" = "export" ]; then
  sed 's#<string>upload</string>#<string>export</string>#' ExportOptions-AppStore.plist > "build/ExportOptions-$platform.plist"
  options="build/ExportOptions-$platform.plist"
fi
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$options" \
  -exportPath "build/export-$platform" \
  "${auth[@]}" | xcbeautify
