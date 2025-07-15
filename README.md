# SwiftSyntaxBinaries

This repository automatically tracks and builds XCFramework releases corresponding to official [apple/swift-syntax](https://github.com/apple/swift-syntax) tags. Each release provides a pre-built XCFramework that can be easily integrated into Swift packages or Xcode projects.

## Overview

- GitHub Actions workflow automatically tracks new SwiftSyntax releases and builds corresponding XCFrameworks.
- Runs weekly with a 2-week cooldown period after each release to avoid excessive builds.
- Also supports manual triggering with specific SwiftSyntax tags.
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

### Automatic Builds
1. The workflow runs weekly on Mondays to check for new SwiftSyntax releases.
2. If a new release is found and we're not in a cooldown period, it proceeds to build.
3. Cooldown period: 2 weeks after any release to prevent excessive builds.

### Manual Builds
1. The workflow can be triggered manually with a specific SwiftSyntax tag.
2. Manual builds bypass the cooldown period.

### Build Steps
1. The build script clones the specified tag from apple/swift-syntax.
2. Builds are performed for macOS (arm64, x86_64) using `swift build` via a temporary wrapper package.
3. An XCFramework is created from the resulting static libraries and module files.
4. The XCFramework is zipped and its checksum is computed.
5. The zipped framework and checksum are attached to a GitHub release matching the tag.

## License

MIT License. See [LICENSE](LICENSE) for details.
