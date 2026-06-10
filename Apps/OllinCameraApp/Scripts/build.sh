#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, and staple OllinCamera.app — the whole pipeline a
# system extension needs before macOS will activate it with SIP enabled.
#
# One-time setup:
#   brew install xcodegen
#   xcrun notarytool store-credentials "ollin-notary" \
#       --apple-id "<apple-id>" --team-id 3ET6D79498 \
#       --password "<app-specific password from appleid.apple.com>"
#
# The Mac must be registered as a device in the developer account (Xcode does
# this on first automatic signing) so -allowProvisioningUpdates can mint the
# provisioning profile that authorizes the restricted
# com.apple.developer.system-extension.install entitlement on the host.
#
# Override the notary profile name with NOTARY_PROFILE if needed.

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
ARCHIVE="$ROOT/build/OllinCamera.xcarchive"
EXPORT="$ROOT/build/export"
APP="$EXPORT/OllinCamera.app"
ZIP="$EXPORT/OllinCamera.zip"
PROFILE="${NOTARY_PROFILE:-ollin-notary}"

echo "▸ Generate the Xcode project"
xcodegen generate

echo "▸ Archive (automatic signing provisions the host's restricted entitlement)"
xcodebuild -project OllinCamera.xcodeproj -scheme OllinCamera \
    -configuration Release -archivePath "$ARCHIVE" archive \
    -allowProvisioningUpdates -quiet

echo "▸ Export with Developer ID signing"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist Scripts/ExportOptions.plist -allowProvisioningUpdates

echo "▸ Submit to the Apple notary service (waits for the result)"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ Staple the ticket onto the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo
echo "✓ Notarized + stapled: $APP"
echo "  Install and activate (install from the repo build, never an iCloud-synced"
echo "  folder — file-provider xattrs break bundle validation):"
echo "    rm -rf /Applications/OllinCamera.app"
echo "    ditto --noextattr --norsrc \"$APP\" /Applications/OllinCamera.app"
echo "    open /Applications/OllinCamera.app"
echo "  First time: approve in System Settings ▸ General ▸ Login Items & Extensions"
echo "  ▸ Camera Extensions, then pick 'Ollin Camera' in Photo Booth."
