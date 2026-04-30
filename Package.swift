// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let rustFFIPath = "Frameworks/AppAttestVerifierFFI.xcframework"
let hasLocalRustFFI = FileManager.default.fileExists(atPath: rustFFIPath)

// The Rust verifier is generated locally and intentionally not committed.
// SwiftPM manifests are evaluated before build scripts run, so this package
// exposes the binary target only after Scripts/build-xcframework.sh has created
// the XCFramework at the expected path.
var targets: [Target] = []

if hasLocalRustFFI {
    targets.append(
        .binaryTarget(
            name: "AppAttestVerifierFFI",
            path: rustFFIPath
        )
    )
}

targets.append(
    .target(
        name: "AppAttestVerifyKit",
        dependencies: hasLocalRustFFI ? ["AppAttestVerifierFFI"] : [],
        resources: [
            .process("Resources"),
        ]
    )
)

targets.append(
    .testTarget(
        name: "AppAttestVerifyKitTests",
        dependencies: ["AppAttestVerifyKit"],
        resources: [
            .process("Fixtures"),
        ]
    )
)

let package = Package(
    name: "AppAttestVerifyKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AppAttestVerifyKit",
            targets: ["AppAttestVerifyKit"]
        ),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
