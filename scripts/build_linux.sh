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
WORK_DIR="$REPO_ROOT_DIR/temp_build_linux"
SWIFT_SYNTAX_DIR="$WORK_DIR/swift-syntax"
WRAPPER_PKG_DIR="$WORK_DIR/SwiftSyntaxWrapperPkg"
FINAL_TAR_NAME="SwiftSyntax-linux.tar.gz"
REPO_URL="https://github.com/apple/swift-syntax.git"

# Determine Swift tools version 
SWIFT_VERSION=$(swift --version | head -n 1 | sed -E 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/')
echo "Detected Swift version: $SWIFT_VERSION"
SWIFT_TOOLS_VERSION="5.7" # Default
if [[ $(echo "$SWIFT_VERSION >= 5.9" | bc -l) -eq 1 ]]; then
    SWIFT_TOOLS_VERSION="5.9"
elif [[ $(echo "$SWIFT_VERSION >= 5.8" | bc -l) -eq 1 ]]; then
    SWIFT_TOOLS_VERSION="5.8"
fi
echo "Using Swift tools version: $SWIFT_TOOLS_VERSION"

# Clean up any previous build
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

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

# Step 3: Build for Linux
echo "Building for Linux..."
cd "$WRAPPER_PKG_DIR"

echo "Resolving package dependencies..."
swift package resolve

echo "Building Linux static library with swift build..."
swift build -c release --static-swift-stdlib

# Step 4: Find the built library
echo "Looking for built library..."
LIB_FILE=$(find .build/release -name "libSwiftSyntaxWrapper.a" | head -n 1)
if [ -z "$LIB_FILE" ]; then
    echo "Could not find library in expected location, searching entire build directory..."
    LIB_FILE=$(find .build -type f -name "*.a" | grep -i "SwiftSyntaxWrapper" | head -n 1)
fi

if [ -z "$LIB_FILE" ]; then
    echo "Error: Could not find built library"
    echo "Available .a files:"
    find .build -name "*.a" | sort
    exit 1
fi

echo "Found library at: $LIB_FILE"
file "$LIB_FILE"

# Step 5: Find Swift modules
echo "Looking for Swift modules..."
MODULE_DIR=$(find .build/release -path "*/SwiftSyntaxWrapper.swiftmodule" -type d | head -n 1)
if [ -z "$MODULE_DIR" ]; then
    echo "Module directory not found at expected path. Searching..."
    MODULE_DIR=$(find .build -path "*SwiftSyntaxWrapper.swiftmodule" -type d | head -n 1)
fi

if [ -z "$MODULE_DIR" ]; then
    echo "Warning: Could not find Swift module directory"
    echo "Available .swiftmodule directories:"
    find .build -name "*.swiftmodule" -type d | sort
    
    # Create basic module structure
    MODULE_DIR="$WORK_DIR/SwiftSyntaxWrapper.swiftmodule"
    mkdir -p "$MODULE_DIR"
    
    # Create basic module files
    cat > "$MODULE_DIR/x86_64-unknown-linux-gnu.swiftinterface" << EOF
// swift-interface-format-version: 1.0
// swift-compiler-version: Apple Swift version $SWIFT_VERSION
// swift-module-flags: -target x86_64-unknown-linux-gnu -enable-objc-interop -enable-library-evolution -swift-version 5 -enforce-exclusivity=checked -O -module-name SwiftSyntaxWrapper
// swift-module-flags-ignorable: -enable-bare-slash-regex
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

    # Create documentation file
    touch "$MODULE_DIR/x86_64-unknown-linux-gnu.swiftdoc"
    
    echo "Created basic module structure at: $MODULE_DIR"
else
    echo "Found module at: $MODULE_DIR"
fi

# Step 6: Create distribution structure
echo "Creating distribution structure..."
DIST_DIR="$WORK_DIR/SwiftSyntax-linux"
mkdir -p "$DIST_DIR/lib"
mkdir -p "$DIST_DIR/include"

# Copy library
cp "$LIB_FILE" "$DIST_DIR/lib/libSwiftSyntaxWrapper.a"

# Copy Swift modules
if [ -d "$MODULE_DIR" ]; then
    cp -r "$MODULE_DIR" "$DIST_DIR/include/"
    echo "Copied Swift modules to distribution"
else
    echo "Warning: No Swift modules to copy"
fi

# Create usage instructions
cat > "$DIST_DIR/README.md" << EOF
# SwiftSyntax Linux Binary

This package contains a prebuilt static library of SwiftSyntax for Linux.

## Contents

- \`lib/libSwiftSyntaxWrapper.a\` - Static library containing SwiftSyntax
- \`include/SwiftSyntaxWrapper.swiftmodule/\` - Swift module interfaces

## Usage

### With Swift Package Manager

Add this to your \`Package.swift\`:

\`\`\`swift
.systemLibrary(
    name: "SwiftSyntaxWrapper",
    pkgConfig: "SwiftSyntaxWrapper",
    providers: [
        .apt(["swift-syntax-dev"]) // Or your preferred package manager
    ]
)
\`\`\`

### Manual Integration

1. Copy \`libSwiftSyntaxWrapper.a\` to your library search path
2. Copy the \`.swiftmodule\` directory to your module search path
3. Link against the library: \`-lSwiftSyntaxWrapper\`

### Swift Build Flags

When building, you may need:

\`\`\`bash
swift build -Xlinker -L/path/to/lib -Xlinker -lSwiftSyntaxWrapper
\`\`\`

## Version

SwiftSyntax version: $SWIFT_SYNTAX_VERSION
Built with Swift: $SWIFT_VERSION
EOF

# Step 7: Create tarball
echo "Creating tarball..."
cd "$WORK_DIR"
tar -czf "$FINAL_TAR_NAME" "SwiftSyntax-linux"

echo "Computing checksum..."
if command -v sha256sum &> /dev/null; then
    CHECKSUM=$(sha256sum "$FINAL_TAR_NAME" | cut -d' ' -f1)
elif command -v shasum &> /dev/null; then
    CHECKSUM=$(shasum -a 256 "$FINAL_TAR_NAME" | cut -d' ' -f1)
else
    echo "Warning: No checksum utility found"
    CHECKSUM="unknown"
fi

echo "Build complete."
echo "Linux Binary: $WORK_DIR/$FINAL_TAR_NAME"
echo "Checksum: $CHECKSUM"

# Output usage example
cat << EOF

Example usage in a Linux Swift project:

1. Download and extract:
   wget https://github.com/ARISTIDE021/SwiftSyntaxBinaries/releases/download/${SWIFT_SYNTAX_VERSION}/${FINAL_TAR_NAME}
   tar -xzf ${FINAL_TAR_NAME}

2. In your Package.swift:
   .systemLibrary(name: "SwiftSyntaxWrapper")

3. Build with:
   swift build -Xlinker -L./SwiftSyntax-linux/lib -Xlinker -lSwiftSyntaxWrapper

EOF

# For GitHub Actions
if [[ "$TEST_MODE" == "false" && -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "linux_binary=$WORK_DIR/$FINAL_TAR_NAME" >> "$GITHUB_OUTPUT"
  echo "linux_checksum=$CHECKSUM" >> "$GITHUB_OUTPUT"
  echo "Output variables set for GitHub Actions."
fi

echo "Linux build completed successfully!"
exit 0