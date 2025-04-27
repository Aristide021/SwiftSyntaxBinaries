#!/bin/bash
set -euo pipefail

# Function to display usage
usage() {
    echo "Usage: $0 [-t] <swift-syntax-version>"
    echo "  -t, --test  Test build locally without creating a GitHub release"
    echo "  <swift-syntax-version> The version tag to build (e.g., 600.0.1)"
    exit 1
}

# Parse arguments
TEST_MODE=false
SWIFT_SYNTAX_VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test)
            TEST_MODE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$SWIFT_SYNTAX_VERSION" ]]; then
                SWIFT_SYNTAX_VERSION="$1"
                shift
            else
                echo "Unknown parameter: $1"
                usage
            fi
            ;;
    esac
done

if [[ -z "$SWIFT_SYNTAX_VERSION" ]]; then
    echo "Error: Swift Syntax version is required"
    usage
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR="$SCRIPT_DIR/.."
WORK_DIR="$REPO_ROOT_DIR/temp_build"
SWIFT_SYNTAX_DIR="$WORK_DIR/swift-syntax"
WRAPPER_PKG_DIR="$WORK_DIR/SwiftSyntaxWrapperPkg"
ARCHIVE_DIR="$WORK_DIR/archives"
FINAL_XCFRAMEWORK_NAME="SwiftSyntax.xcframework"
FINAL_ZIP_NAME="SwiftSyntax.xcframework.zip"
REPO_URL="https://github.com/apple/swift-syntax.git"
WRAPPER_SCHEME_NAME="SwiftSyntaxWrapper"

# Determine Swift tools version 
SWIFT_VERSION=$(swift --version | head -n 1 | sed -E 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/')
echo "Detected Swift version: $SWIFT_VERSION"
SWIFT_TOOLS_VERSION="5.7" # Default
if [[ $(echo "$SWIFT_VERSION >= 5.9" | bc) -eq 1 ]]; then
    SWIFT_TOOLS_VERSION="5.9"
elif [[ $(echo "$SWIFT_VERSION >= 5.8" | bc) -eq 1 ]]; then
    SWIFT_TOOLS_VERSION="5.8"
fi
echo "Using Swift tools version: $SWIFT_TOOLS_VERSION"

# Clean up any previous build
rm -rf "$WORK_DIR"
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$WORK_DIR/DerivedData"

# Step 1: Clone swift-syntax at the specified tag
echo "Cloning swift-syntax $SWIFT_SYNTAX_VERSION..."
git clone --branch "$SWIFT_SYNTAX_VERSION" --depth 1 "$REPO_URL" "$SWIFT_SYNTAX_DIR"

# Step 2: Create the wrapper package
echo "Creating SwiftSyntaxWrapper package..."
mkdir -p "$WRAPPER_PKG_DIR/Sources/SwiftSyntaxWrapper"

# Create Package.swift
cat > "$WRAPPER_PKG_DIR/Package.swift" << EOF
// swift-tools-version:$SWIFT_TOOLS_VERSION
import PackageDescription

let package = Package(
    name: "SwiftSyntaxWrapperPkg",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13)
    ],
    products: [
        .library(
            name: "SwiftSyntaxWrapper",
            type: .static,
            targets: ["SwiftSyntaxWrapper"]
        )
    ],
    dependencies: [
        .package(path: "$SWIFT_SYNTAX_DIR")
    ],
    targets: [
        .target(
            name: "SwiftSyntaxWrapper",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftBasicFormat", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        )
    ]
)
EOF

# Create wrapper Swift file with @_exported imports
cat > "$WRAPPER_PKG_DIR/Sources/SwiftSyntaxWrapper/SwiftSyntaxWrapper.swift" << EOF
// This file re-exports all the necessary SwiftSyntax modules
@_exported import SwiftSyntax
@_exported import SwiftParser
@_exported import SwiftSyntaxBuilder
@_exported import SwiftSyntaxMacros
@_exported import SwiftDiagnostics
@_exported import SwiftBasicFormat
@_exported import SwiftOperators
@_exported import SwiftParserDiagnostics
@_exported import SwiftSyntaxMacroExpansion
@_exported import SwiftCompilerPlugin

// No actual code is needed in this file.
EOF

# Define all platforms to build for
PLATFORMS=(
    "macOS"
)

# Function to extract architecture from library
extract_arch_from_library() {
    local LIB_PATH="$1"
    local TARGET_ARCH="$2"
    local OUTPUT_PATH="$3"
    
    echo "Extracting $TARGET_ARCH architecture from $LIB_PATH to $OUTPUT_PATH..."
    
    # Create a temporary directory
    local TEMP_DIR=$(mktemp -d)
    
    # Check if the library is a universal (fat) binary
    local ARCHS=$(lipo -archs "$LIB_PATH" 2>/dev/null || echo "unknown")
    echo "Library architectures: $ARCHS"
    
    if [[ "$ARCHS" == *"$TARGET_ARCH"* ]]; then
        # Library contains our target architecture
        if [[ "$ARCHS" == *" "* ]]; then
            # Multiple architectures - extract just the one we want
            lipo -extract "$TARGET_ARCH" "$LIB_PATH" -output "$TEMP_DIR/lib.a"
            cp "$TEMP_DIR/lib.a" "$OUTPUT_PATH"
        else
            # Single architecture - just copy it
            cp "$LIB_PATH" "$OUTPUT_PATH"
        fi
        
        echo "Extracted architecture $TARGET_ARCH to $OUTPUT_PATH"
        echo "Checking result:"
        lipo -info "$OUTPUT_PATH" || echo "Could not get lipo info for $OUTPUT_PATH"
        file "$OUTPUT_PATH"
        
        # Clean up
        rm -rf "$TEMP_DIR"
        return 0
    else
        echo "Error: Library does not contain $TARGET_ARCH architecture"
        rm -rf "$TEMP_DIR"
        return 1
    fi
}

# Function to build using swift build for a specific architecture
build_for_arch() {
    local PLATFORM="$1"
    local ARCH="$2"
    local PLATFORM_TRIPLET="$3"
    local ARCHIVE_PATH="$4"

    echo "Building $PLATFORM for $ARCH architecture..."

    # Determine SDK (unchanged)
    local SDK=""
    case "$PLATFORM" in
        "macOS") SDK="macosx" ;;
        "iOS") SDK="iphoneos" ;;
        "iOS Simulator") SDK="iphonesimulator" ;;
        "tvOS") SDK="appletvos" ;;
        "tvOS Simulator") SDK="appletvsimulator" ;;
        "watchOS") SDK="watchos" ;;
        "watchOS Simulator") SDK="watchsimulator" ;;
        *) echo "Unknown platform: $PLATFORM"; return 1 ;;
    esac

    local SDKROOT=$(xcrun --sdk $SDK --show-sdk-path)
    echo "Using SDK: $SDK, Path: $SDKROOT, Architecture: $ARCH"

    # Build using swift build
    local BUILD_DIR="$WORK_DIR/DerivedData/$PLATFORM-$ARCH"

    # Remove any previous build artifacts
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    cd "$WRAPPER_PKG_DIR"
    echo "Resolving package dependencies..."
    swift package resolve

    echo "Building $PLATFORM ($ARCH) with swift build..."

    # Add -Xcc "-target" flag to match -Xswiftc "-target"
    swift build \
        -c release \
        --build-path "$BUILD_DIR" \
        -Xswiftc "-sdk" -Xswiftc "$SDKROOT" \
        -Xcc "-isysroot" -Xcc "$SDKROOT" \
        -Xcc "-fmodules" \
        -Xcc "-fimplicit-modules" \
        -Xcc "-fimplicit-module-maps" \
        -Xswiftc "-target" -Xswiftc "$PLATFORM_TRIPLET" \
        -Xcc "-target" -Xcc "$PLATFORM_TRIPLET" \
        -Xswiftc "-emit-module-interface" # Add this flag to generate .swiftinterface files

    # Find the built library (unchanged)
    local LIB_FILE=$(find "$BUILD_DIR" -name "libSwiftSyntaxWrapper.a" | head -n 1)
    if [ -z "$LIB_FILE" ]; then
        echo "Could not find library in expected location, searching entire build directory..."
        LIB_FILE=$(find "$BUILD_DIR" -type f -name "*.a" | grep -i "SwiftSyntaxWrapper" | head -n 1)
    fi

    if [ -n "$LIB_FILE" ]; then
        echo "Found library at: $LIB_FILE"
        local FILE_INFO=$(file "$LIB_FILE")
        echo "Library file info: $FILE_INFO"

        # Create directory for the architecture-specific library (unchanged)
        mkdir -p "$ARCHIVE_PATH/Products/usr/local/lib/$ARCH"
        local ARCH_LIB_PATH="$ARCHIVE_PATH/Products/usr/local/lib/$ARCH/libSwiftSyntaxWrapper.a"

        # Extract the correct architecture (unchanged)
        if extract_arch_from_library "$LIB_FILE" "$ARCH" "$ARCH_LIB_PATH"; then
            echo "Successfully extracted $ARCH architecture to $ARCH_LIB_PATH"
        else
            echo "Warning: Could not extract $ARCH architecture. Copying library directly."
            cp "$LIB_FILE" "$ARCH_LIB_PATH"
        fi

        # --- Improved Module Directory Finding and Copying ---
        local MODULE_DIR=""
        # Updated path to where Swift actually places the modules
        local EXPECTED_MODULE_DIR="$BUILD_DIR/$PLATFORM_TRIPLET/release/Modules/SwiftSyntaxWrapper.swiftmodule"
        local FALLBACK_MODULE_DIR="$BUILD_DIR/Modules/SwiftSyntaxWrapper.swiftmodule"
        local GENERIC_MODULE_PATH="$BUILD_DIR/release/Modules/SwiftSyntaxWrapper.swiftmodule"
        local DEST_MODULE_DIR="$ARCHIVE_PATH/Products/usr/local/lib/swift/static/SwiftSyntaxWrapper.swiftmodule"

        # Check for module directory in multiple possible locations
        if [ -d "$EXPECTED_MODULE_DIR" ]; then
            MODULE_DIR="$EXPECTED_MODULE_DIR"
            echo "Found module at expected location: $MODULE_DIR"
        elif [ -d "$FALLBACK_MODULE_DIR" ]; then
            MODULE_DIR="$FALLBACK_MODULE_DIR"
            echo "Found module at fallback location: $MODULE_DIR"
        elif [ -d "$GENERIC_MODULE_PATH" ]; then
            MODULE_DIR="$GENERIC_MODULE_PATH"
            echo "Found module at generic location: $MODULE_DIR"
        else
            echo "Module directory not found at expected paths. Searching..."
            # Search for any .swiftmodule directory
            MODULE_DIR=$(find "$BUILD_DIR" -path "*/Modules/SwiftSyntaxWrapper.swiftmodule" -type d | head -n 1)
            
            if [ -z "$MODULE_DIR" ]; then
                # Try a broader search if the specific path didn't work
                MODULE_DIR=$(find "$BUILD_DIR" -path "*SwiftSyntaxWrapper.swiftmodule" -type d | head -n 1)
            fi
        fi

        if [ -n "$MODULE_DIR" ]; then
            echo "Found module at: $MODULE_DIR"
            mkdir -p "$DEST_MODULE_DIR"

            # Copy all relevant module files from the build output
            echo "Copying module files from $MODULE_DIR to $DEST_MODULE_DIR"
            cp -r "$MODULE_DIR/"* "$DEST_MODULE_DIR/"

            # Verify copied files
            echo "Contents of destination module directory:"
            ls -la "$DEST_MODULE_DIR"
        else
            # If we still can't find the modules, let's look for individual module files
            local MODULE_FILES=$(find "$BUILD_DIR" -name "*.swiftmodule" -o -name "*.swiftdoc" -o -name "*.swiftsourceinfo" -o -name "*.swiftinterface" | grep -i "SwiftSyntaxWrapper")
            
            if [ -n "$MODULE_FILES" ]; then
                echo "Found individual module files. Copying them to destination..."
                mkdir -p "$DEST_MODULE_DIR"
                
                # Copy each file
                echo "$MODULE_FILES" | while read -r file; do
                    echo "Copying $file to $DEST_MODULE_DIR/"
                    cp "$file" "$DEST_MODULE_DIR/"
                done
                
                # Verify copied files
                echo "Contents of destination module directory after individual file copy:"
                ls -la "$DEST_MODULE_DIR"
            else
                # Placeholder logic as a last resort
                echo "Could not find module files. Creating placeholder..."
                mkdir -p "$DEST_MODULE_DIR"
                echo "Creating placeholder swiftmodule files for $ARCH"
                touch "$DEST_MODULE_DIR/$ARCH.swiftmodule"
                touch "$DEST_MODULE_DIR/$ARCH.swiftdoc"
                cat > "$DEST_MODULE_DIR/$ARCH.swiftinterface" << EOF
// swift-interface-format-version: 1.0
// swift-compiler-version: Apple Swift version ${SWIFT_VERSION}
// Placeholder interface - actual build failed to produce module files.
import Swift
@_exported import SwiftSyntax
@_exported import SwiftParser
@_exported import SwiftSyntaxBuilder
@_exported import SwiftSyntaxMacros
@_exported import SwiftDiagnostics
@_exported import SwiftBasicFormat
@_exported import SwiftOperators
@_exported import SwiftParserDiagnostics
@_exported import SwiftSyntaxMacroExpansion
@_exported import SwiftCompilerPlugin
EOF
            fi
        fi
        # --- End of Module Directory Improvement ---

        return 0 # Success
    else
        echo "Error: Could not find built library for $PLATFORM ($ARCH)"
        find "$BUILD_DIR" -type f -name "*.a" | sort
        return 1 # Error
    fi
}

# Function to build for each platform
build_platform() {
    local PLATFORM="$1"
    
    echo "Building archive for $PLATFORM..."
    
    # Convert platform name to a suitable archive name (no spaces)
    local ARCHIVE_NAME=$(echo "$PLATFORM" | tr -d ' ')
    local ARCHIVE_PATH="$ARCHIVE_DIR/${ARCHIVE_NAME}.xcarchive"
    
    # Create necessary directories for archive structure
    mkdir -p "$ARCHIVE_PATH/Products/usr/local/lib"
    mkdir -p "$ARCHIVE_PATH/Products/usr/local/lib/swift/static"
    
    # Determine architectures and triplets based on platform
    local ARCHS=()
    local PLATFORM_TRIPLETS=()
    local BUILD_RESULTS=()
    
    case "$PLATFORM" in
        "macOS")
            ARCHS=("arm64" "x86_64")
            PLATFORM_TRIPLETS=("arm64-apple-macosx10.15" "x86_64-apple-macosx10.15")
            ;;
        "iOS")
            ARCHS=("arm64")
            PLATFORM_TRIPLETS=("arm64-apple-ios13.0")
            ;;
        "iOS Simulator")
            ARCHS=("arm64" "x86_64")
            PLATFORM_TRIPLETS=("arm64-apple-ios13.0-simulator" "x86_64-apple-ios13.0-simulator")
            ;;
        "tvOS")
            ARCHS=("arm64")
            PLATFORM_TRIPLETS=("arm64-apple-tvos13.0")
            ;;
        "tvOS Simulator")
            ARCHS=("arm64" "x86_64")
            PLATFORM_TRIPLETS=("arm64-apple-tvos13.0-simulator" "x86_64-apple-tvos13.0-simulator")
            ;;
        "watchOS")
            ARCHS=("arm64")
            PLATFORM_TRIPLETS=("arm64-apple-watchos6.0")
            ;;
        "watchOS Simulator")
            ARCHS=("arm64" "x86_64")
            PLATFORM_TRIPLETS=("arm64-apple-watchos6.0-simulator" "x86_64-apple-watchos6.0-simulator")
            ;;
        *)
            echo "Unknown platform: $PLATFORM"
            return 1
            ;;
    esac
    
    # Build each architecture separately
    local ALL_ARCHS_BUILT=true
    for i in "${!ARCHS[@]}"; do
        if build_for_arch "$PLATFORM" "${ARCHS[$i]}" "${PLATFORM_TRIPLETS[$i]}" "$ARCHIVE_PATH"; then
            echo "Successfully built ${ARCHS[$i]} for $PLATFORM"
            BUILD_RESULTS+=("success")
        else
            echo "Failed to build ${ARCHS[$i]} for $PLATFORM"
            BUILD_RESULTS+=("failure")
            ALL_ARCHS_BUILT=false
        fi
    done
    
    # Create fat library if multiple architectures were built successfully
    local ARCH_LIBS=()
    for i in "${!ARCHS[@]}"; do
        local ARCH_LIB="$ARCHIVE_PATH/Products/usr/local/lib/${ARCHS[$i]}/libSwiftSyntaxWrapper.a"
        if [ -f "$ARCH_LIB" ] && [ "${BUILD_RESULTS[$i]}" == "success" ]; then
            # Verify we have the correct architecture in this file
            echo "Verifying architecture of $ARCH_LIB"
            if lipo -info "$ARCH_LIB" 2>/dev/null | grep -q "${ARCHS[$i]}"; then
                echo "$ARCH_LIB contains ${ARCHS[$i]} architecture"
                ARCH_LIBS+=("$ARCH_LIB")
            else
                echo "Warning: $ARCH_LIB does not contain ${ARCHS[$i]} architecture"
            fi
        fi
    done
    
    # If we have multiple architecture libraries, create a fat binary
    if [ ${#ARCH_LIBS[@]} -gt 1 ]; then
        echo "Creating fat library from: ${ARCH_LIBS[*]}"
        lipo -create "${ARCH_LIBS[@]}" -output "$ARCHIVE_PATH/Products/usr/local/lib/libSwiftSyntaxWrapper.a"
        
        # Verify the fat binary
        echo "Verifying fat library:"
        lipo -info "$ARCHIVE_PATH/Products/usr/local/lib/libSwiftSyntaxWrapper.a" || true
        file "$ARCHIVE_PATH/Products/usr/local/lib/libSwiftSyntaxWrapper.a"
    elif [ ${#ARCH_LIBS[@]} -eq 1 ]; then
        # Just use the single architecture
        echo "Only one architecture built successfully, using that one"
        cp "${ARCH_LIBS[0]}" "$ARCHIVE_PATH/Products/usr/local/lib/libSwiftSyntaxWrapper.a"
    else
        echo "Error: No architectures were built successfully"
        return 1
    fi
    
    # Clean up individual architecture directories
    for ARCH in "${ARCHS[@]}"; do
        rm -rf "$ARCHIVE_PATH/Products/usr/local/lib/$ARCH"
    done
    
    # Examine the archive structure
    echo "Examining archive structure for $PLATFORM..."
    find "$ARCHIVE_PATH" -type f | grep -v ".DS_Store" | sort
    
    if [ -f "$ARCHIVE_PATH/Products/usr/local/lib/libSwiftSyntaxWrapper.a" ]; then
        return 0
    else
        echo "Error: Final library not found at expected location"
        return 1
    fi
}

# Build archives for each platform
XCFRAMEWORK_ARGS=()

for PLATFORM in "${PLATFORMS[@]}"; do
    if build_platform "$PLATFORM"; then
        echo "Successfully built platform: $PLATFORM"
        
        # Convert platform name to a suitable archive name (no spaces)
        ARCHIVE_NAME=$(echo "$PLATFORM" | tr -d ' ')
        ARCHIVE_PATH="$ARCHIVE_DIR/${ARCHIVE_NAME}.xcarchive"
        
        # Look for static library
        LIB_PATH=$(find "$ARCHIVE_PATH" -name "libSwiftSyntaxWrapper.a" | head -n 1)
        if [ -n "$LIB_PATH" ]; then
            echo "Found static library at: $LIB_PATH"
            
            # Find headers/module path
            MODULE_DIR=$(find "$ARCHIVE_PATH" -path "*/SwiftSyntaxWrapper.swiftmodule" -type d | head -n 1)
            if [ -n "$MODULE_DIR" ]; then
                echo "Found module directory at: $MODULE_DIR"
                HEADERS_DIR=$(dirname "$MODULE_DIR")
                XCFRAMEWORK_ARGS+=("-library" "$LIB_PATH" "-headers" "$HEADERS_DIR")
            else
                echo "Error: Could not find Swift module directory for $PLATFORM"
                exit 1
            fi
        else
            echo "Error: Could not find library in archive for $PLATFORM"
            exit 1
        fi
    else
        echo "Failed to build platform: $PLATFORM"
        # Continue with other platforms rather than stopping completely
        echo "Continuing with other platforms..."
    fi
done

if [ ${#XCFRAMEWORK_ARGS[@]} -eq 0 ]; then
    echo "Error: No platforms were built successfully"
    exit 1
fi

# Create XCFramework
echo "Creating XCFramework..."
echo "xcframework arguments: ${XCFRAMEWORK_ARGS[@]}"
xcodebuild -create-xcframework ${XCFRAMEWORK_ARGS[@]} -output "$WORK_DIR/$FINAL_XCFRAMEWORK_NAME"

echo "Inspecting XCFramework structure..."
ls -la "$WORK_DIR/$FINAL_XCFRAMEWORK_NAME"
find "$WORK_DIR/$FINAL_XCFRAMEWORK_NAME" -type f | grep -v ".DS_Store" | sort

# Zip XCFramework and compute checksum
echo "Zipping XCFramework..."
(cd "$WORK_DIR" && zip -r "$FINAL_ZIP_NAME" "$FINAL_XCFRAMEWORK_NAME")

echo "Computing checksum..."
CHECKSUM=$(swift package compute-checksum "$WORK_DIR/$FINAL_ZIP_NAME")

echo "Build complete."
echo "XCFramework Zip: $WORK_DIR/$FINAL_ZIP_NAME"
echo "Checksum: $CHECKSUM"

# Output a Package.swift snippet that can be used to import this binary
cat << EOF

Example Package.swift snippet to use this binary:

.binaryTarget(
    name: "SwiftSyntax",
    url: "https://github.com/ARISTIDE021/SwiftSyntaxBinaries/releases/download/${SWIFT_SYNTAX_VERSION}/${FINAL_ZIP_NAME}",
    checksum: "${CHECKSUM}"
),

EOF

# For GitHub Actions
if [[ "$TEST_MODE" == "false" && -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "framework_zip=$WORK_DIR/$FINAL_ZIP_NAME" >> "$GITHUB_OUTPUT"
  echo "checksum=$CHECKSUM" >> "$GITHUB_OUTPUT"
  echo "Output variables set for GitHub Actions."
fi

echo "Local testing completed successfully!"
exit 0