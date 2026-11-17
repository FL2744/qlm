#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool profile name}"
VERSION="$(cat VERSION)"
./build.sh
QLM_TEST_OUTPUT="$PWD/build" ./build/qlm.app/Contents/MacOS/qlm --self-test
mkdir -p release-work downloads
APP="$PWD/build/qlm.app"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" release-work/qlm-notarization.zip
xcrun notarytool submit release-work/qlm-notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > release-work/notarization.json
python3 -c 'import json; r=json.load(open("release-work/notarization.json")); assert r.get("status")=="Accepted", r'
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "downloads/qlm-v${VERSION}-macOS-universal.zip"
(cd downloads && shasum -a 256 "qlm-v${VERSION}-macOS-universal.zip" > SHA256SUMS.txt)
