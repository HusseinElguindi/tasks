#!/bin/sh
# Regenerates every app icon file (02a Lit body) from gen.py. Run from anywhere:
#   design/logo/final/export.sh
# Needs python3 for gen.py, and Xcode for swiftc, iconutil and Icon Composer's ictool.
set -eu
cd "$(dirname "$0")"
rm -rf svg AppIcon.icon
python3 gen.py

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O render.swift -o "$tmp/render"

# macOS PNGs in iconset naming, one set for both appearances. Below 60px the small cut is used (16, 16@2x and 32).
rm -rf png
mkdir -p png
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    px=${spec%%:*}
    name=${spec#*:}
    svg="svg/icon.svg"
    [ "$px" -lt 60 ] && svg="svg/icon-small.svg"
    "$tmp/render" "$svg" "png/icon_$name.png" "$px"
done

# The same set as the classic .icns, for anything that reads one directly.
mkdir -p "$tmp/AppIcon.iconset"
cp png/*.png "$tmp/AppIcon.iconset/"
iconutil -c icns "$tmp/AppIcon.iconset" -o AppIcon.icns

# The Mac app's copy (app/project.yml names it AppIcon).
rm -rf ../../../app/Tasks/AppIcon.icon
cp -R AppIcon.icon ../../../app/Tasks/AppIcon.icon

# The iPhone app's 1024s (ios/Tasks/Assets.xcassets/AppIcon.appiconset): any and dark are the same lit body (the
# user: lit body in light and dark); tinted is the greyscale cut the system tints.
ios=../../../ios/Tasks/Assets.xcassets/AppIcon.appiconset
"$tmp/render" svg/ios.svg "$ios/icon-1024.png" 1024
cp "$ios/icon-1024.png" "$ios/icon-1024-dark.png"
"$tmp/render" svg/ios-tinted.svg "$ios/icon-1024-tinted.png" 1024

# What macOS 26 and later draws from AppIcon.icon, in each appearance.
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
rm -rf system
mkdir -p system
for r in Default Dark TintedLight TintedDark ClearLight ClearDark; do
    "$ictool" AppIcon.icon --export-image --output-file "system/$r.png" --platform macOS --rendition "$r" \
        --width 512 --height 512 --scale 1 >/dev/null
done
