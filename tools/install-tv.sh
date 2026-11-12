#!/bin/zsh
# Build the tvOS app and install it on a paired Apple TV. Run from your own terminal (signing
# needs the login keychain). Usage: tools/install-tv.sh ["Living Room"]   (default: first Apple TV)
set -e
cd "${0:A:h}/../apple"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
NAME=$1
DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk -v n="$NAME" '/AppleTV/ && /physical/ && (n == "" || index($0, n)) {for(i=1;i<=NF;i++) if($i ~ /^([0-9A-F]{8}-[0-9A-F]{16}|[0-9a-f]{40})$/) print $i}' | head -1)
[[ -z $DEVICE ]] && { echo "No paired Apple TV found${NAME:+ named $NAME}"; exit 1; }
mkdir -p ../.build
xcodegen -q
xcodebuild -project KicksRide.xcodeproj -scheme KicksRideTV -destination "id=$DEVICE" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -derivedDataPath ../.build/dd build > ../.build/install-tv.log 2>&1 \
  || { grep -E "error|failed" ../.build/install-tv.log | head -20; echo "Build failed (full log: .build/install-tv.log)"; exit 1; }
echo "Build succeeded"
xcrun devicectl device install app --device "$DEVICE" ../.build/dd/Build/Products/Debug-appletvos/KicksRideTV.app >/dev/null
echo "Installed on $DEVICE"
