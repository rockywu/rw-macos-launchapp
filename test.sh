#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pinchlaunch-test.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
xcrun clang -std=c17 -Wall -Wextra -Werror -O2 -ISources Sources/Detector.c Tests/DetectorTests.c -o "$scratch/detector-test"
"$scratch/detector-test"
xcrun clang -std=c17 -Wall -Wextra -Werror -O2 -ISources Sources/PinchRoute.c Tests/PinchRouteTests.c -o "$scratch/route-test"
"$scratch/route-test"
xcrun swiftc Sources/Layout.swift Sources/PageSwipe.swift Tests/LayoutTests.swift -o "$scratch/layout-test"
"$scratch/layout-test"
