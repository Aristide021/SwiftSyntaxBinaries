# SwiftSyntax XCFramework Builder

This repository automatically builds and hosts XCFramework releases corresponding to official [apple/swift-syntax](https://github.com/apple/swift-syntax) tags. Each release provides a pre-built XCFramework that can be easily integrated into Swift packages or Xcode projects.

## Overview

- Automated GitHub Actions workflow builds XCFrameworks for each official SwiftSyntax tag.
- Supports macOS, iOS, and iOS Simulator platforms.
- Each release includes a zipped XCFramework and its checksum for use as a binary target.

## Usage

To use a pre-built SwiftSyntax XCFramework in your Swift package:

```swift
.binaryTarget(
    name: "SwiftSyntax",
    url: "https://github.com/YOUR_USERNAME/SwiftSyntaxBinaries/releases/download/<TAG>/SwiftSyntax.xcframework.zip",
    checksum: "<CHECKSUM>"
)
```

Replace `<TAG>` and `<CHECKSUM>` with the release tag and checksum from the corresponding release.

## Build Process

1. The workflow is triggered manually with a SwiftSyntax tag.
2. The build script clones the specified tag from apple/swift-syntax.
3. Archives are built for macOS, iOS, and iOS Simulator using Xcode.
4. An XCFramework is created from the archives.
5. The XCFramework is zipped and its checksum is computed.
6. The zipped framework and checksum are attached to a GitHub release matching the tag.

## License

MIT License. See [LICENSE](LICENSE) for details.
