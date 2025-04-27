# SwiftSyntaxBinaries

This repository builds and hosts XCFramework releases corresponding to official [apple/swift-syntax](https://github.com/apple/swift-syntax) tags. Each release provides a pre-built XCFramework that can be easily integrated into Swift packages or Xcode projects.

## Overview

- GitHub Actions workflow builds XCFrameworks based on manually specified official SwiftSyntax tags.
- Supports macOS (Universal: arm64 + x86_64).
- Each release includes a zipped XCFramework and its checksum for use as a binary target.

## Usage

To use a pre-built SwiftSyntax XCFramework in your Swift package:

```swift
.binaryTarget(
    name: "SwiftSyntaxWrapper",
    url: "https://github.com/ARISTIDE021/SwiftSyntaxBinaries/releases/download/<TAG>/SwiftSyntax.xcframework.zip",
    checksum: "<CHECKSUM>"
)
```

Replace `<TAG>` and `<CHECKSUM>` with the release tag and checksum from the corresponding release.

## Build Process

1. The workflow is triggered manually with a SwiftSyntax tag.
2. The build script clones the specified tag from apple/swift-syntax.
3. Builds are performed for macOS (arm64, x86_64) using `swift build` via a temporary wrapper package.
4. An XCFramework is created from the resulting static libraries and module files.
5. The XCFramework is zipped and its checksum is computed.
6. The zipped framework and checksum are attached to a GitHub release matching the tag.

## License

MIT License. See [LICENSE](LICENSE) for details.
