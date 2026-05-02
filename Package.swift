// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
    targets: [
        // Release builds consume the Rust verifier from the matching GitHub
        // Release asset so SwiftPM users do not need a local Rust toolchain.
        .binaryTarget(
            name: "AppAttestVerifierFFI",
            url: "https://github.com/TAP-NAP/AppAttestVerifyKit/releases/download/v0.1.0/AppAttestVerifierFFI.xcframework.zip",
            checksum: "bcff73754d858b824d5eeff0cd20ae21d67f33bfbcaf106bf3cbac88e93c0fa2"
        ),
        .target(
            name: "AppAttestVerifyKit",
            dependencies: ["AppAttestVerifierFFI"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AppAttestVerifyKitTests",
            dependencies: ["AppAttestVerifyKit"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
