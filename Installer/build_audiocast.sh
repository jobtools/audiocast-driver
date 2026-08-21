#!/usr/bin/env bash
# Build the AudioCast virtual audio driver as a single-variant fork of BlackHole.
# Outputs Installer/AudioCast-<version>.pkg.
#
# Signed with the Developer ID keys when they are in the keychain, which is what
# ./release-driver ships: the AudioCast app installs this package as root, so a
# signed and notarized package is the only thing that lets the app refuse
# anything else. Falls back to the self-signed "AudioCast Dev" identity and an
# unsigned package for local builds, which is fine for `sudo installer` by hand
# and nothing else.
set -euo pipefail

driverName="AudioCast"
bundleID="com.audiocast.driver"
manufacturer="AudioCast"
channels=2

devCertName="AudioCast Dev"
certP12="${AUDIOCAST_CERT_P12:-../AudioCast/sender/macos/certs/AudioCastDev.p12}"
certPass="${AUDIOCAST_CERT_PASS:-audiocast}"

# SIGN_IDENTITY signs the .driver bundle, INSTALLER_IDENTITY signs the .pkg —
# two different certificate types, both needed for a release build. Either can
# be overridden; otherwise they are picked from the keychain.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)"
fi
[[ -n "${SIGN_IDENTITY}" ]] || SIGN_IDENTITY="$devCertName"

if [[ -z "${INSTALLER_IDENTITY:-}" ]]; then
    INSTALLER_IDENTITY="$(security find-identity -v \
        | sed -n 's/.*"\(Developer ID Installer: .*\)"$/\1/p' | head -1)"
fi

# Hardened runtime and a timestamp only make sense for the Developer ID key: the
# self-signed cert has no chain Apple's timestamp server will vouch for, and the
# notary service rejects anything signed without the runtime.
HARDENED=0
case "${SIGN_IDENTITY}" in
    "Developer ID Application: "*) HARDENED=1 ;;
esac

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
# Keyed off the *resolved* identity: asking for the dev cert explicitly on a
# machine that also holds the Developer ID key has to install it too.
if [[ "$SIGN_IDENTITY" == "$devCertName" ]] \
   && ! security find-identity -v -p codesigning | grep -q "$devCertName"; then
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
# No --deep: it is deprecated, and this bundle is a single Mach-O with no nested
# code for it to reach anyway.
echo ">> Signing $driverName.driver with: $SIGN_IDENTITY"
signArgs=(--force --sign "$SIGN_IDENTITY")
if [[ $HARDENED -eq 1 ]]; then
    signArgs+=(--timestamp --options runtime)
fi
codesign "${signArgs[@]}" "Installer/root/$driverName.driver"
codesign --verify --strict --verbose=2 "Installer/root/$driverName.driver"

# --- Build .pkg ---------------------------------------------------------------
chmod 755 Installer/Scripts/preinstall Installer/Scripts/postinstall 2>/dev/null || true

pkgName="$driverName-$version.pkg"
echo ">> Packaging $pkgName..."
pkgArgs=(
    --root Installer/root
    --scripts Installer/Scripts
    --install-location /Library/Audio/Plug-Ins/HAL
    --identifier "$bundleID"
    --version "$version"
)
if [[ -n "${INSTALLER_IDENTITY}" ]]; then
    echo ">> Signing $pkgName with: $INSTALLER_IDENTITY"
    pkgArgs+=(--sign "${INSTALLER_IDENTITY}" --timestamp)
elif [[ $HARDENED -eq 1 ]]; then
    # A Developer-ID-signed driver inside an unsigned package is a half-measure
    # that reads as a release build but cannot be notarized. Say so rather than
    # let it reach ./release-driver, which checks for both up front.
    echo ">> WARNING: no 'Developer ID Installer' certificate — package will be unsigned." >&2
fi
pkgbuild "${pkgArgs[@]}" "Installer/$pkgName"

rm -rf Installer/root

echo ""
echo ">> Done."
echo ">> Output:  Installer/$pkgName"
echo ">> Install: sudo installer -pkg Installer/$pkgName -target /"
