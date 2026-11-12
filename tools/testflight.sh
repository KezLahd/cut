#!/bin/zsh
# Archives Cut and uploads it to TestFlight, so Kez's phone gets it over the internet when he's away from
# the Mac (TestFlight app, automatic updates on). Internal testing needs no review: a build shows up
# 5–15 minutes after upload. Signs with the Apple ID in Xcode (see tools/phone.sh); uploads with the shared
# App Store Connect API key. Needs the Cut app record in App Store Connect (made on the website).
#
#     tools/testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source ~/.appstoreconnect/asc.env
key=~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
auth=()
# The archive signs with the Apple ID in Xcode; the App Store export needs the API key (without it: "No Accounts").
keyauth=(-authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
command -v xcodegen >/dev/null && xcodegen -q
tools/secrets.sh
work=build/testflight
rm -rf $work && mkdir -p $work
build=$(date +%Y%m%d%H%M)

print "Archiving build $build…"
xcodebuild -project Cut.xcodeproj -scheme Cut -configuration Release -destination "generic/platform=iOS" \
  -archivePath $work/Cut.xcarchive CURRENT_PROJECT_VERSION=$build -allowProvisioningUpdates "${auth[@]}" archive \
  | grep -E "error:|ARCHIVE" || true
[[ -d $work/Cut.xcarchive ]] || { print "Archive failed."; exit 1; }

cat > $work/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>8QPPD49JQ5</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

print "Signing for the App Store…"
xcodebuild -exportArchive -archivePath $work/Cut.xcarchive -exportPath $work/export \
  -exportOptionsPlist $work/ExportOptions.plist -allowProvisioningUpdates "${keyauth[@]}" | grep -E "error:|EXPORT" || true
ipa=$(ls $work/export/*.ipa 2>/dev/null | head -1)
[[ -n $ipa ]] || { print "Export failed."; exit 1; }

print "Uploading to TestFlight…"
out=$(xcrun altool --upload-app --type ios --file "$ipa" --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID 2>&1 || true)
print -r -- "$out" | grep -E -i "error|UPLOAD SUCCEEDED|No errors" || true
if print -r -- "$out" | grep -qiE "UPLOAD SUCCEEDED|No errors uploading"; then
  print "Done. Build $build reaches TestFlight once Apple has processed it (usually 5–15 minutes)."
else
  print "Upload failed."; exit 1
fi
