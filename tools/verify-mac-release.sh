#!/bin/sh
# Check the actual distribution containers, including a quarantined app extracted from the ZIP.
# usage: tools/verify-mac-release.sh ZIP DMG
set -eu
cd "$(dirname "$0")/.."
[ "$#" = 2 ] || { echo "usage: tools/verify-mac-release.sh ZIP DMG" >&2; exit 1; }
zip=$1
dmg=$2
version=$(cat VERSION)
work=$(mktemp -d)
mounted=0
cleanup() {
    if [ "$mounted" = 1 ]; then hdiutil detach -quiet "$work/dmg" || true; fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

verify_app() {
    codesign --verify --strict --deep --verbose=2 "$1"
    team=$(codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [ "$team" = G29V3JRMJJ ] || { echo "verify-mac-release: unexpected developer ($team)" >&2; exit 1; }
    xcrun stapler validate "$1"
    spctl --assess --type execute --verbose=2 "$1"
    test "$(plutil -extract CFBundleShortVersionString raw "$1/Contents/Info.plist")" = "${version%%-*}"
    test "$("$1/Contents/MacOS/raftaar" --version)" = "raftaar $version"
}

ditto -x -k "$zip" "$work/zip"
xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");raftaar-release-verification;" "$work/zip/rhun.app"
verify_app "$work/zip/rhun.app"

codesign --verify --strict --verbose=2 "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
mkdir "$work/dmg"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$work/dmg" "$dmg"
mounted=1
verify_app "$work/dmg/rhun.app"
cmp "$work/zip/rhun.app/Contents/MacOS/raftaar" "$work/dmg/rhun.app/Contents/MacOS/raftaar"
echo "ok   macOS ZIP and DMG: signed, notarized, stapled and accepted by Gatekeeper"
