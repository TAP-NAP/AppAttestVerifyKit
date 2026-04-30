#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CRATE_DIR="$ROOT_DIR/Rust/AppAttestVerifierFFI"
FRAMEWORK_DIR="$ROOT_DIR/Frameworks"
OUTPUT="$FRAMEWORK_DIR/AppAttestVerifierFFI.xcframework"
HEADER_DIR="$CRATE_DIR/include"
SIM_UNIVERSAL_DIR="$CRATE_DIR/target/universal-apple-ios-sim/release"
SIM_UNIVERSAL_LIB="$SIM_UNIVERSAL_DIR/libapp_attest_verifier_ffi.a"

mkdir -p "$FRAMEWORK_DIR"
rm -rf "$OUTPUT"

# Keep the Rust static libraries aligned with Package.swift platform floors.
export MACOSX_DEPLOYMENT_TARGET=14.0
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export IOS_DEPLOYMENT_TARGET=16.0

cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target aarch64-apple-darwin
cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target aarch64-apple-ios
cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target aarch64-apple-ios-sim
cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target x86_64-apple-ios

mkdir -p "$SIM_UNIVERSAL_DIR"
lipo -create \
  "$CRATE_DIR/target/aarch64-apple-ios-sim/release/libapp_attest_verifier_ffi.a" \
  "$CRATE_DIR/target/x86_64-apple-ios/release/libapp_attest_verifier_ffi.a" \
  -output "$SIM_UNIVERSAL_LIB"

xcodebuild -create-xcframework \
  -library "$CRATE_DIR/target/aarch64-apple-darwin/release/libapp_attest_verifier_ffi.a" \
  -headers "$HEADER_DIR" \
  -library "$CRATE_DIR/target/aarch64-apple-ios/release/libapp_attest_verifier_ffi.a" \
  -headers "$HEADER_DIR" \
  -library "$SIM_UNIVERSAL_LIB" \
  -headers "$HEADER_DIR" \
  -output "$OUTPUT"

echo "Built $OUTPUT"
