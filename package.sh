#!/bin/bash
set -euo pipefail

template="$(cd -P -- "$(dirname -- "$0")" && pwd)/Assets/修复 RWLaunch.command.in"
app=${1-}
output=${2-}
app=${app%/}
output=${output%/}
if [[ $# != 2 || "$app" != /*/RWLaunch.app || ! -d "$app" || -L "$app" || "$output" != /* ]]; then
    printf 'Usage: ./package.sh /absolute/path/RWLaunch.app /absolute/path/new-output-dir\n' >&2
    exit 1
fi

/usr/bin/codesign --verify --strict --deep --all-architectures \
    -R='identifier "local.pinchlaunch.launcher"' "$app"
cdhash() {
    local arch=$1 info digest
    info=$(/usr/bin/codesign --display --arch "$arch" --verbose=4 "$app" 2>&1) || return 1
    digest=$(/usr/bin/sed -n 's/^CDHash=//p' <<< "$info")
    if [[ "$digest" =~ ^[a-f0-9]{40}$ ]] && /usr/bin/grep -qx 'Signature=adhoc' <<< "$info"; then
        printf '%s\n' "$digest"
    else
        printf 'Expected an ad hoc-signed universal trial build (%s).\n' "$arch" >&2
        return 1
    fi
}
arm64=$(cdhash arm64)
x86_64=$(cdhash x86_64)

/bin/mkdir -p -- "$(/usr/bin/dirname -- "$output")"
/bin/mkdir -- "$output"
helper="$output/Repair RWLaunch.command"
app_zip="$output/RWLaunch-trial.zip"
helper_zip="$output/RWLaunch-repair.zip"
cleanup() {
    local file
    for file in "$helper" "$app_zip" "$helper_zip"; do
        if [[ -f "$file" ]]; then /usr/bin/unlink "$file"; fi
    done
    /bin/rmdir "$output"
}
trap cleanup EXIT

/usr/bin/sed -e "s/@ARM64_CDHASH@/$arm64/g" -e "s/@X86_64_CDHASH@/$x86_64/g" "$template" > "$helper"
/bin/chmod 755 "$helper"
/usr/bin/ditto -c -k --keepParent "$app" "$app_zip"
/usr/bin/zip -jq "$helper_zip" "$helper"
trap - EXIT
printf '%s\n' "$app_zip" "$helper_zip"
