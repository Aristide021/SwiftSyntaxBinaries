// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftSyntaxBinaries",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "SwiftSyntaxWrapper",
            targets: ["SwiftSyntaxWrapper"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "SwiftSyntaxWrapper",
            url: "https://github.com/Aristide021/SwiftSyntaxBinaries/releases/download/601.0.1/SwiftSyntax.xcframework.zip",
            checksum: "16b62d34b32d0e5ddff11972eacc13393e2025ecc988ba2bee11e7d25b53cfbd"
        )
    ]
)