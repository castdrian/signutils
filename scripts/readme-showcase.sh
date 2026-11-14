#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
shots=("$@")
[ ${#shots[@]} -gt 0 ] || shots=(iphone_01_library iphone_02_bundle iphone_06_ready)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
frame="$(base64 < assets/device-iPhone16-dark.png | tr -d '\n')"
count=${#shots[@]}
width=$((count * 510 - 30))
{
  echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"930\" viewBox=\"0 0 $width 930\" role=\"img\" aria-labelledby=\"title description\">"
  echo "<title id=\"title\">SignUtils screenshots</title>"
  echo "<desc id=\"description\">The SignUtils library, a signing bundle and a finished archive shown in iPhone frames.</desc>"
  echo "<defs>"
  echo "<filter id=\"shadow\" x=\"-25%\" y=\"-15%\" width=\"150%\" height=\"145%\">"
  echo "<feDropShadow dx=\"0\" dy=\"12\" stdDeviation=\"10\" flood-color=\"#000000\" flood-opacity=\"0.3\"/>"
  echo "</filter>"
  for index in "${!shots[@]}"; do
    x=$((39 + index * 510))
    echo "<clipPath id=\"screen-$index\"><rect x=\"$x\" y=\"35\" width=\"403\" height=\"871\" rx=\"54\"/></clipPath>"
  done
  echo "</defs>"
  for index in "${!shots[@]}"; do
    x=$((39 + index * 510))
    frame_x=$((25 + index * 510))
    sips -s format jpeg -s formatOptions 82 -Z 1612 "fastlane/screenshots/ios/en-US/${shots[$index]}.png" --out "$work/$index.jpg" >/dev/null
    shot="$(base64 < "$work/$index.jpg" | tr -d '\n')"
    echo "<g filter=\"url(#shadow)\">"
    echo "<image x=\"$x\" y=\"35\" width=\"403\" height=\"871\" preserveAspectRatio=\"xMidYMid slice\" clip-path=\"url(#screen-$index)\" href=\"data:image/jpeg;base64,$shot\"/>"
    echo "<image x=\"$frame_x\" y=\"20\" width=\"430\" height=\"900\" preserveAspectRatio=\"none\" href=\"data:image/png;base64,$frame\"/>"
    echo "</g>"
  done
  echo "</svg>"
} > assets/screenshots.svg
echo "Wrote assets/screenshots.svg ($(du -h assets/screenshots.svg | cut -f1))"
