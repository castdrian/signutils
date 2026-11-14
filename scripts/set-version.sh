#!/bin/sh
set -eu
version="$1"
build="${2:-$(git rev-list --count HEAD)}"
printf 'MARKETING_VERSION = %s\nCURRENT_PROJECT_VERSION = %s\n' "$version" "$build" > Config.xcconfig
