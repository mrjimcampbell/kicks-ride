#!/bin/zsh
# Build the iPhone app and install it on the first connected physical iPhone.
# Run from your own terminal (signing needs the login keychain). Also the 7-day refresh.
set -e
cd "${0:A:h}/../apple"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /physical/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)
[[ -z $DEVICE ]] && { echo "No iPhone connected"; exit 1; }
xcodegen -q
xcodebuild -project KicksRide.xcodeproj -scheme KicksRide -destination "id=$DEVICE" \
  -allowProvisioningUpdates -derivedDataPath ../.build/dd build > ../.build/install.log 2>&1 \
  || { grep -E "error|failed" ../.build/install.log | head -20; echo "Build failed (full log: .build/install.log)"; exit 1; }
echo "Build succeeded"
xcrun devicectl device install app --device "$DEVICE" ../.build/dd/Build/Products/Debug-iphoneos/KicksRide.app >/dev/null
echo "Installed on $DEVICE"
