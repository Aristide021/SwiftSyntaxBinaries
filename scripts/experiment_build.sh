#!/bin/bash
set -euo pipefail

# Test variables
SWIFT_SYNTAX_VERSION="600.0.1"
WORK_DIR="$(pwd)/temp_experiment"
REPO_URL="https://github.com/apple/swift-syntax.git"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "Cloning swift-syntax $SWIFT_SYNTAX_VERSION..."
git clone --branch "$SWIFT_SYNTAX_VERSION" --depth 1 "$REPO_URL" "$WORK_DIR/swift-syntax"

cd "$WORK_DIR/swift-syntax"

echo "=== Attempt 1: Build SwiftSyntax scheme directly via Package.swift ==="
xcodebuild archive \
  -scheme SwiftSyntax \
  -sdk iphoneos \
  -arch arm64 \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  SKIP_INSTALL=NO || echo "Direct build failed or scheme missing."

echo "Artifacts from direct build:"
find . -name "*.framework" || true
find . -name "*.swiftinterface" || true

echo "=== Attempt 2: Add SwiftSyntaxWrapper static library target and build ==="
cat >> Package.swift << 'EOF'

// SwiftSyntaxWrapper target for static lib experiment
// This is a placeholder; actual implementation may require editing the manifest properly.
EOF

# Note: In a real experiment, you would programmatically insert a valid wrapper target.
# For now, this is a placeholder to indicate where the wrapper logic would go.

# Attempt to build the wrapper (will likely fail unless the manifest is properly edited)
xcodebuild archive \
  -scheme SwiftSyntaxWrapper \
  -sdk iphoneos \
  -arch arm64 \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  SKIP_INSTALL=NO || echo "Wrapper build failed or scheme missing."

echo "Artifacts from wrapper build:"
find . -name "*.a" || true
find . -name "*.swiftinterface" || true

echo "Experiment complete. Review output above for artifact locations and build success."
