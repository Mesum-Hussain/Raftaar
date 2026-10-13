#!/bin/sh
# macOS release: raftaar.app signed with a Developer ID (hardened runtime), notarized and stapled, in
# build/raftaar-VERSION-macos-arm64.zip (for install.sh and updates) and build/raftaar-VERSION-macos-arm64.dmg.
# usage: tools/package-mac.sh
#   RAFTAAR_SIGN_ID          signing identity (default: the first Developer ID Application certificate)
#   RAFTAAR_NOTARY_PROFILE   notarytool keychain profile (default raftaar-notary), stored once with
#                         xcrun notarytool store-credentials raftaar-notary --apple-id ID --team-id TEAM
#   RAFTAAR_NOTARY_KEY, RAFTAAR_NOTARY_KEY_ID, RAFTAAR_NOTARY_ISSUER
#                         an App Store Connect API key (the .p8 file, its key id, the issuer id) in
#                         place of the profile; the release workflow uses these
#   RAFTAAR_NOTARIZE=0       sign only for local use, and no disk image; forbidden with RAFTAAR_DIST=1
set -eu
cd "$(dirname "$0")/.."
notarize=${RAFTAAR_NOTARIZE:-1}
case "$notarize" in 0|1) ;; *) echo "package-mac: RAFTAAR_NOTARIZE must be 0 or 1" >&2; exit 1 ;; esac
if [ "${RAFTAAR_DIST:-0}" = 1 ] && [ "$notarize" != 1 ]; then
    echo "package-mac: distribution builds must be notarized" >&2
    exit 1
fi
if [ "$notarize" = 1 ] && [ -n "${RAFTAAR_NOTARY_KEY:-}" ]; then
    [ -s "$RAFTAAR_NOTARY_KEY" ] || { echo "package-mac: notary API key is missing or empty" >&2; exit 1; }
    : "${RAFTAAR_NOTARY_KEY_ID:?missing notary API key id}"
    : "${RAFTAAR_NOTARY_ISSUER:?missing notary API issuer id}"
fi
id=${RAFTAAR_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)}
[ -n "$id" ] || { echo "package-mac: no Developer ID Application certificate in the keychain" >&2; exit 1; }
profile=${RAFTAAR_NOTARY_PROFILE:-raftaar-notary}
if [ "$notarize" = 1 ] && [ -z "${RAFTAAR_NOTARY_KEY:-}" ] &&
    ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "package-mac: no notarytool profile '$profile'; store one with" >&2
    echo "  xcrun notarytool store-credentials $profile --apple-id YOUR_APPLE_ID --team-id TEAM_ID" >&2
    echo "or run with RAFTAAR_NOTARIZE=0 to sign only" >&2
    exit 1
fi
version=$(cat VERSION)
app=build/raftaar.app
zip=build/raftaar-$version-macos-arm64.zip
dmg=build/raftaar-$version-macos-arm64.dmg

tools/build-mac.sh release
codesign --force --options runtime --timestamp --sign "$id" "$app"
codesign --verify --strict --verbose=2 "$app"

submit() { # file: notarize and wait
    if [ -n "${RAFTAAR_NOTARY_KEY:-}" ]; then
        xcrun notarytool submit "$1" --key "$RAFTAAR_NOTARY_KEY" --key-id "$RAFTAAR_NOTARY_KEY_ID" \
            --issuer "$RAFTAAR_NOTARY_ISSUER" --wait --timeout 20m --output-format json > build/notary.json || {
                cat build/notary.json >&2; return 1;
            }
    else
        xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --timeout 20m --output-format json > build/notary.json || {
            cat build/notary.json >&2; return 1;
        }
    fi
    cat build/notary.json
    python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1]))["status"] == "Accepted" else 1)' build/notary.json
}
if [ "$notarize" = 1 ]; then
    ditto -c -k --keepParent "$app" build/raftaar.zip
    submit build/raftaar.zip
    rm build/raftaar.zip
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
# the app for install.sh and updates; ditto keeps the signature and the stapled ticket
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "$zip"
[ "$notarize" = 1 ] || exit 0

# the disk image: the app and a link to Applications
stage=$(mktemp -d)
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname raftaar -srcfolder "$stage" -format UDZO -o "$dmg"
rm -rf "$stage"
codesign --force --timestamp --sign "$id" "$dmg"
submit "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
echo "$dmg"
