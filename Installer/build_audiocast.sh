#!/usr/bin/env bash
# Build the AudioCast virtual audio driver as a single-variant fork of BlackHole.
# Outputs Installer/AudioCast-<version>.pkg, signed with the self-signed
# "AudioCast Dev" identity (no Apple Developer Program required).
set -euo pipefail

driverName="AudioCast"
bundleID="com.audiocast.driver"
manufacturer="AudioCast"
channels=2

certName="AudioCast Dev"
certP12="${AUDIOCAST_CERT_P12:-../AudioCast/sender/macos/certs/AudioCastDev.p12}"
certPass="${AUDIOCAST_CERT_PASS:-audiocast}"

# --- Validation ---------------------------------------------------------------
if [[ ! -d BlackHole.xcodeproj ]]; then
    echo "Run from the audiocast-driver repo root." >&2
    exit 1
fi
version="$(cat VERSION)"
if [[ -z "$version" ]]; then
    echo "VERSION file is empty." >&2
    exit 1
fi

# --- Ensure cert is in keychain -----------------------------------------------
if ! security find-identity -v -p codesigning | grep -q "$certName"; then
    if [[ ! -f "$certP12" ]]; then
        echo "Cert not found at $certP12 — set AUDIOCAST_CERT_P12 to override." >&2
        exit 1
    fi
    echo ">> Importing codesign certificate..."
    security import "$certP12" -k ~/Library/Keychains/login.keychain-db \
        -P "$certPass" -T /usr/bin/codesign 2>/dev/null || true
    openssl pkcs12 -in "$certP12" -clcerts -nokeys -passin "pass:$certPass" -legacy 2>/dev/null \
        | openssl x509 -out /tmp/_audiocast_driver_cert.pem 2>/dev/null
    security add-trusted-cert -d -r trustRoot -p codeSign \
        -k ~/Library/Keychains/login.keychain-db /tmp/_audiocast_driver_cert.pem 2>/dev/null || true
    rm -f /tmp/_audiocast_driver_cert.pem
fi

# --- Build .driver ------------------------------------------------------------
rm -rf build Installer/root Installer/*.pkg

echo ">> Building $driverName.driver..."
xcodebuild \
    -project BlackHole.xcodeproj \
    -configuration Release \
    -target BlackHole \
    CONFIGURATION_BUILD_DIR=build \
    PRODUCT_NAME="$driverName" \
    PRODUCT_BUNDLE_IDENTIFIER="$bundleID" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS
    kNumber_Of_Channels='"$channels"'
    kPlugIn_BundleID=\"'"$bundleID"'\"
    kDriver_Name=\"'"$driverName"'\"
    kDevice_Name=\"'"$driverName"'\"
    kManufacturer_Name=\"'"$manufacturer"'\"'

# Generate fresh plugin UUID
uuid="$(uuidgen)"
awk '{sub(/e395c745-4eea-4d94-bb92-46224221047c/,"'"$uuid"'")}1' \
    "build/$driverName.driver/Contents/Info.plist" > /tmp/_audiocast_info.plist
mv /tmp/_audiocast_info.plist "build/$driverName.driver/Contents/Info.plist"

# Stage in Installer/root for pkgbuild
mkdir -p Installer/root
mv "build/$driverName.driver" "Installer/root/$driverName.driver"
rm -rf build

# --- Sign .driver -------------------------------------------------------------
echo ">> Signing $driverName.driver..."
codesign --force --deep --sign "$certName" "Installer/root/$driverName.driver"

# --- Build .pkg ---------------------------------------------------------------
chmod 755 Installer/Scripts/preinstall Installer/Scripts/postinstall 2>/dev/null || true

pkgName="$driverName-$version.pkg"
echo ">> Packaging $pkgName..."
pkgbuild \
    --root Installer/root \
    --scripts Installer/Scripts \
    --install-location /Library/Audio/Plug-Ins/HAL \
    --identifier "$bundleID" \
    --version "$version" \
    "Installer/$pkgName"

rm -rf Installer/root

echo ""
echo ">> Done."
echo ">> Output:  Installer/$pkgName"
echo ">> Install: sudo installer -pkg Installer/$pkgName -target /"
