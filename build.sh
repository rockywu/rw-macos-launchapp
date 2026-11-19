#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
target="${1:-$PWD/build/RWLaunch.app}"
[[ "$target" = /* && "$target" = *.app && ! -e "$target" ]] || {
    printf 'Provide an absolute path to a new .app directory.\n' >&2
    exit 1
}
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pinchlaunch-build.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
sdk="$(xcrun --sdk macosx --show-sdk-path)"
bundle="$scratch/RWLaunch.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$scratch/AppIcon.iconset"
cp Assets/Info.plist "$bundle/Contents/Info.plist"
cp Assets/OpenMultitouchSupport-LICENSE.txt "$bundle/Contents/Resources/"
xcrun swift Assets/Icon.swift "$scratch/AppIcon.iconset"
iconutil -c icns "$scratch/AppIcon.iconset" -o "$bundle/Contents/Resources/RWLaunch.icns"
for arch in arm64 x86_64; do
    archTarget="$arch-apple-macos15.0"
    for source in Detector TouchBridge PinchRoute SystemPinch; do
        xcrun clang -O2 -Wall -Wextra -Werror -target "$archTarget" -isysroot "$sdk" -c "Sources/$source.c" -o "$scratch/$source-$arch.o"
    done
    xcrun swiftc -parse-as-library -O -target "$archTarget" -sdk "$sdk" \
        -import-objc-header Sources/TouchBridge.h Sources/*.swift \
        "$scratch/Detector-$arch.o" "$scratch/TouchBridge-$arch.o" "$scratch/PinchRoute-$arch.o" "$scratch/SystemPinch-$arch.o" \
        -framework ApplicationServices -framework IOKit \
        -o "$scratch/RWLaunch-$arch"
done
xcrun lipo -create "$scratch/RWLaunch-arm64" "$scratch/RWLaunch-x86_64" -output "$bundle/Contents/MacOS/RWLaunch"
codesign --force --sign - --timestamp=none "$bundle"
mkdir -p "$(dirname "$target")"
mv -n -- "$bundle" "$target"
printf '%s\n' "$target"
