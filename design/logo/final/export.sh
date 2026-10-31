#!/bin/sh
# Regenerates every 04 Log icon file from gen.py. Run from anywhere:
#   design/logo/final/export.sh
# Needs uv (mise) for gen.py and Xcode for swiftc, actool and ictool.
set -eu
cd "$(dirname "$0")"
uv run -q --with shapely python gen.py

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O render.swift -o "$tmp/render"

# PNGs in iconset naming, light and dark. Below 60px the small cut is used (16, 16@2x and 32).
for look in light dark; do
    out="png/$look"
    mkdir -p "$out"
    for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
        px=${spec%%:*}
        name=${spec#*:}
        svg="svg/icon-$look.svg"
        [ "$px" -lt 60 ] && svg="svg/icon-$look-small.svg"
        "$tmp/render" "$svg" "$out/icon_$name.png" "$px"
    done
done

# The light set is also the classic .icns, for anything that reads one directly.
mkdir -p "$tmp/AppIcon.iconset"
cp png/light/*.png "$tmp/AppIcon.iconset/"
iconutil -c icns "$tmp/AppIcon.iconset" -o AppIcon.icns

# The app's copy (app/project.yml names it AppIcon).
rm -rf ../../../app/Tasks/AppIcon.icon
cp -R AppIcon.icon ../../../app/Tasks/AppIcon.icon

# What macOS 26 and later draws from AppIcon.icon, in each appearance.
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
mkdir -p system
for r in Default Dark TintedLight TintedDark ClearLight ClearDark; do
    "$ictool" AppIcon.icon --export-image --output-file "system/$r.png" --platform macOS --rendition "$r" \
        --width 512 --height 512 --scale 1 >/dev/null
done
