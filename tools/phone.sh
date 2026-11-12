#!/bin/zsh
# Builds Cut (Release) and installs it on your iPhone over Wi-Fi.
#     tools/phone.sh          build and install
#     tools/phone.sh build    build only
set -euo pipefail
cd "$(dirname "$0")/.."
# Your device id (xcrun devicectl list devices) goes in CUT_PHONE or tools/.phone, which git ignores.
PHONE=${CUT_PHONE:-$(cat tools/.phone 2>/dev/null || true)}
[[ -n $PHONE || ${1:-} == build ]] || { echo "Put your device id in tools/.phone or CUT_PHONE."; exit 1; }
command -v xcodegen >/dev/null && xcodegen -q
tools/secrets.sh
# Signs with the Apple ID signed in to Xcode. The shared ASC key stopped working for new profiles in
# Xcode 27.1 ("Authentication failed"), and the API can't create App Groups, so Cut uses the account.
# Set CUT_ASC_KEY=1 to try the key instead.
auth=()
env=~/.appstoreconnect/asc.env
if [[ ${CUT_ASC_KEY:-} == 1 && -f $env ]]; then
  source $env
  key=~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
  auth=(-authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodebuild -project Cut.xcodeproj -scheme Cut -configuration Release -destination "generic/platform=iOS" \
  -derivedDataPath build/phone -allowProvisioningUpdates "${auth[@]}" build 2>&1 | grep -E "error|warning: .*Cut/|BUILD" | head -40
[[ -d build/phone/Build/Products/Release-iphoneos/Cut.app ]] || { echo "Build failed."; exit 1; }
[[ ${1:-} == build ]] && exit 0
xcrun devicectl device install app --device $PHONE build/phone/Build/Products/Release-iphoneos/Cut.app 2>&1 | grep -iE "installed|error"
