#!/usr/bin/env bash
set -euo pipefail

# Builds the Rust-backed XCFramework, packages it in SwiftPM's expected zip
# format, computes the checksum, and prints the Package.swift binaryTarget
# snippet needed for a GitHub Release asset.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG=""
REPOSITORY="TAP-NAP/AppAttestVerifyKit"
REPOSITORY_WAS_SET=false
UPDATE_PACKAGE=false
ARTIFACT_NAME="AppAttestVerifierFFI.xcframework"
ARCHIVE_NAME="$ARTIFACT_NAME.zip"
XCFRAMEWORK="$ROOT_DIR/Frameworks/$ARTIFACT_NAME"
RELEASE_DIR="$ROOT_DIR/.release"
ARCHIVE="$RELEASE_DIR/$ARCHIVE_NAME"
CHECKSUM_FILE="$RELEASE_DIR/$ARCHIVE_NAME.checksum"
SNIPPET_FILE="$RELEASE_DIR/AppAttestVerifierFFI.binaryTarget.swift"
PACKAGE_FILE="$ROOT_DIR/Package.swift"

usage() {
    cat <<EOF
Usage:
  Scripts/package-release-binary.sh <tag> [owner/repo] [--update-package]

Example:
  Scripts/package-release-binary.sh v0.1.0 TAP-NAP/AppAttestVerifyKit
  Scripts/package-release-binary.sh v0.1.0 TAP-NAP/AppAttestVerifyKit --update-package

The script writes:
  .release/$ARCHIVE_NAME
  .release/$ARCHIVE_NAME.checksum
  .release/AppAttestVerifierFFI.binaryTarget.swift

Options:
  --update-package   Replace Package.swift with a release manifest that uses
                     the generated GitHub Release binary target URL.
EOF
}

for argument in "$@"; do
    case "$argument" in
        -h|--help)
            usage
            exit 0
            ;;
        --update-package)
            UPDATE_PACKAGE=true
            ;;
        --*)
            echo "Unknown option: $argument" >&2
            usage
            exit 64
            ;;
        *)
            if [[ -z "$TAG" ]]; then
                TAG="$argument"
            elif [[ "$REPOSITORY_WAS_SET" == "false" ]]; then
                REPOSITORY="$argument"
                REPOSITORY_WAS_SET=true
            else
                echo "Unexpected argument: $argument" >&2
                usage
                exit 64
            fi
            ;;
    esac
done

if [[ -z "$TAG" ]]; then
    usage
    exit 64
fi

mkdir -p "$RELEASE_DIR"
rm -f "$ARCHIVE" "$CHECKSUM_FILE" "$SNIPPET_FILE"

"$ROOT_DIR/Scripts/build-xcframework.sh"

if [[ ! -d "$XCFRAMEWORK" ]]; then
    echo "Expected XCFramework was not generated: $XCFRAMEWORK" >&2
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "zip is required to package the XCFramework archive." >&2
    exit 1
fi

# SwiftPM requires the archive root to contain the .xcframework directory.
(
    cd "$ROOT_DIR/Frameworks"
    COPYFILE_DISABLE=1 zip -r -X "$ARCHIVE" "$ARTIFACT_NAME"
)

CHECKSUM="$(swift package --package-path "$ROOT_DIR" compute-checksum "$ARCHIVE")"
RELEASE_URL="https://github.com/$REPOSITORY/releases/download/$TAG/$ARCHIVE_NAME"

printf '%s\n' "$CHECKSUM" > "$CHECKSUM_FILE"

cat > "$SNIPPET_FILE" <<EOF
.binaryTarget(
    name: "AppAttestVerifierFFI",
    url: "$RELEASE_URL",
    checksum: "$CHECKSUM"
)
EOF

if [[ "$UPDATE_PACKAGE" == "true" ]]; then
    cat > "$PACKAGE_FILE" <<EOF
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
$(sed 's/^/        /' "$SNIPPET_FILE"),
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
EOF
fi

cat <<EOF

Built release binary artifact:
  $ARCHIVE

Checksum:
  $CHECKSUM

Release asset URL:
  $RELEASE_URL

Package.swift binaryTarget snippet:

$(cat "$SNIPPET_FILE")

Upload with GitHub CLI after pushing the tag:
  gh release create "$TAG" "$ARCHIVE" --title "$TAG" --notes "Rust-backed App Attest verifier binary"

EOF

if [[ "$UPDATE_PACKAGE" == "true" ]]; then
    cat <<EOF
Package.swift was updated to use the GitHub Release binary target.
Commit Package.swift before creating and pushing tag $TAG.

EOF
fi
