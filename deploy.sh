#!/bin/bash

set -euo pipefail

DEVICE_TYPE=${1:-iphone}

trap 'echo ""; echo "💥 FATAL: Deployment failed at line $LINENO"; echo "Command: $BASH_COMMAND"; echo "Exit code: $?"; echo ""; exit 1' ERR

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "--------------------------------------------------------------------------------"
echo "STEP 1: DEVICE DISCOVERY"
echo "--------------------------------------------------------------------------------"
echo ""

if [ "$DEVICE_TYPE" = "ipad" ]; then
    DEVICECTL_ID=$(xcrun devicectl list devices | grep "iPad" | grep -v "Simulator" | head -1 | awk '{print $4}')
    DEVICE_NAME="iPad"
    DEVICE_FAMILY=2
elif [ "$DEVICE_TYPE" = "iphone" ]; then
    DEVICECTL_ID=$(xcrun devicectl list devices | grep "iPhone 17" | awk '{print $3}')
    DEVICE_NAME="iPhone 17 Pro Max"
    DEVICE_FAMILY=1
else
    echo "❌ Invalid device type: $DEVICE_TYPE"
    echo "   Valid options: ipad, iphone"
    exit 1
fi

if [ -z "$DEVICECTL_ID" ]; then
    echo "❌ FATAL: $DEVICE_NAME not found"
    echo "   Please connect device and try again"
    exit 1
fi

echo "   ✅ Found: $DEVICE_NAME"
echo "   Device ID: $DEVICECTL_ID"

echo ""
echo "--------------------------------------------------------------------------------"
echo "STEP 2: BUILD IOS APPLICATION"
echo "--------------------------------------------------------------------------------"
echo ""

echo "   Building Voices application for $DEVICE_NAME..."
echo ""

# Create temporary file for build output
BUILD_LOG=$(mktemp)

# Try build without clean first (faster)
if /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build -project Voices/Voices.xcodeproj -scheme Voices -destination "generic/platform=iOS" CODE_SIGN_IDENTITY="Apple Development" TARGETED_DEVICE_FAMILY=$DEVICE_FAMILY > "$BUILD_LOG" 2>&1; then
    # Build succeeded
    echo "   ✅ Build successful"

    # Check for warnings even on success
    if grep -q "warning:" "$BUILD_LOG"; then
        echo ""
        echo "   ⚠️  Warnings:"
        grep "warning:" "$BUILD_LOG"
        echo ""
    fi

    rm "$BUILD_LOG"
else
    # Build failed - show errors and warnings
    echo "   ❌ Build failed - showing errors and warnings:"
    echo ""
    grep "error:" "$BUILD_LOG" || true
    grep "warning:" "$BUILD_LOG" || true
    echo ""

    # Try clean and rebuild
    echo "   ⚠️  Trying clean build..."
    echo ""

    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild clean -project Voices/Voices.xcodeproj -scheme Voices -destination "generic/platform=iOS" TARGETED_DEVICE_FAMILY=$DEVICE_FAMILY > /dev/null 2>&1

    if /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build -project Voices/Voices.xcodeproj -scheme Voices -destination "generic/platform=iOS" CODE_SIGN_IDENTITY="Apple Development" TARGETED_DEVICE_FAMILY=$DEVICE_FAMILY > "$BUILD_LOG" 2>&1; then
        echo "   ✅ Clean build successful"

        # Check for warnings even on success
        if grep -q "warning:" "$BUILD_LOG"; then
            echo ""
            echo "   ⚠️  Warnings:"
            grep "warning:" "$BUILD_LOG"
            echo ""
        fi

        rm "$BUILD_LOG"
    else
        # Clean build also failed - print errors and exit
        echo "   ❌ Clean build also failed - showing errors and warnings:"
        echo ""
        grep "error:" "$BUILD_LOG" || true
        grep "warning:" "$BUILD_LOG" || true
        rm "$BUILD_LOG"
        exit 1
    fi
fi

APP_PATH=$(find /Users/felixlunzenfichter/Library/Developer/Xcode/DerivedData -name "Voices.app" -path "*/Build/Products/Debug-iphoneos/*" ! -path "*/Index.noindex/*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "   ❌ Build artifact not found"
    exit 1
fi

echo "   Binary: $APP_PATH"

echo ""
echo "--------------------------------------------------------------------------------"
echo "STEP 3: DEPLOY IOS APP"
echo "--------------------------------------------------------------------------------"
echo ""

echo "   Installing app on $DEVICE_NAME..."
xcrun devicectl device install app --device "$DEVICECTL_ID" "$APP_PATH"
echo "   ✅ App installed"

echo ""

echo "   Launching app..."
xcrun devicectl device process launch --device "$DEVICECTL_ID" iVoices.ch.Voices
echo "   ✅ App launched"

echo ""
echo "--------------------------------------------------------------------------------"
echo "DEPLOYMENT COMPLETE"
echo "--------------------------------------------------------------------------------"
echo ""
echo "   Device: $DEVICE_NAME ($DEVICECTL_ID)"
echo "   App: Voices"
echo ""
