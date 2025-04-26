#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <swift-syntax-version>"
    exit 1
fi

SWIFT_SYNTAX_VERSION="$1"
WORK_DIR="$(pwd)/temp"
ARCHIVE_DIR="$WORK_DIR/archives"
XCFRAMEWORK_NAME="SwiftSyntax.xcframework"
ZIP_NAME="SwiftSyntax.xcframework.zip"
REPO_URL="https://github.com/apple/swift-syntax.git"
FRAMEWORK_NAME="SwiftSyntax"

rm -rf "$WORK_DIR"
mkdir -p "$ARCHIVE_DIR"

echo "Cloning swift-syntax $SWIFT_SYNTAX_VERSION..."
git clone --branch "$SWIFT_SYNTAX_VERSION" --depth 1 "$REPO_URL" "$WORK_DIR/swift-syntax"

PLATFORMS=("macos" "iphoneos" "iphonesimulator")
for PLATFORM in "${PLATFORMS[@]}"; do
    echo "Building for $PLATFORM..."
    xcodebuild archive \
        -project "$WORK_DIR/swift-syntax/SwiftSyntax.xcodeproj" \
        -scheme "$FRAMEWORK_NAME" \
        -destination "generic/platform=$PLATFORM" \
        -archivePath "$ARCHIVE_DIR/$PLATFORM" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO
done

echo "Creating XCFramework..."
XCFRAMEWORK_ARGS=()
for PLATFORM in "${PLATFORMS[@]}"; do
    XCFRAMEWORK_ARGS+=(-archive "$ARCHIVE_DIR/$PLATFORM.xcarchive" -framework "$FRAMEWORK_NAME")
done

xcodebuild -create-xcframework "${XCFRAMEWORK_ARGS[@]}" -output "$WORK_DIR/$XCFRAMEWORK_NAME"

echo "Zipping XCFramework..."
cd "$WORK_DIR"
zip -r "$ZIP_NAME" "$XCFRAMEWORK_NAME"

echo "Computing checksum..."
CHECKSUM=$(swift package compute-checksum "$ZIP_NAME")

echo "::set-output name=framework_zip::$WORK_DIR/$ZIP_NAME"
echo "::set-output name=checksum::$CHECKSUM"
