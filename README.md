# AppAttestVerifyKit

Swift Package for verifying Apple App Attest attestation and assertion CBOR
artifacts locally from Swift. The public Swift API calls a Rust verifier through
a locally generated static XCFramework.

The Rust verifier is pinned to:

```text
TAP-NAP/attestation_assertion_verifier@f93e42f83d1f52cfd3bc41678713f424d30fc921
```

## Package Shape

- `AppAttestVerifier` is the main async Swift API.
- `AttestationVerificationRequest` verifies an attestation CBOR object.
- `AssertionVerificationRequest` verifies an assertion CBOR object using saved
  attestation state.
- `VerifiedAttestationState` contains the public key, credential ID, receipt,
  and counter needed by future assertion checks.
- `ApplicationSupportAttestationStateStore` saves that state as JSON for local
  apps and examples.
- `Frameworks/AppAttestVerifierFFI.xcframework` is generated locally and is not
  committed to Git.

`Package.swift` detects whether the local XCFramework exists. Before it is
generated, the package remains loadable, but verification calls fail with a
clear "run Scripts/build-xcframework.sh" error. After the script runs, SwiftPM
adds the binary target and the Swift wrapper calls into Rust.

If SwiftPM or Xcode evaluated the package before the XCFramework was generated,
reset the package cache or reopen the project so the manifest is evaluated
again.

## Build From A Clean Clone

```sh
git clone https://github.com/TAP-NAP/AppAttestVerifyKit.git
cd AppAttestVerifyKit
```

Install the Rust targets used by the local XCFramework build:

```sh
rustup target add aarch64-apple-darwin
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios
```

Generate the Rust-backed XCFramework:

```sh
Scripts/build-xcframework.sh
```

If you already opened or built the package before running that script, refresh
SwiftPM's view of the manifest:

```sh
swift package reset
```

The generated binary target is:

```text
Frameworks/AppAttestVerifierFFI.xcframework
```

The generated XCFramework and Rust `target` directory are ignored by Git:

```text
Frameworks/AppAttestVerifierFFI.xcframework/
Rust/AppAttestVerifierFFI/target/
```

Run the package tests after generating the XCFramework:

```sh
swift test
```

Build the example app:

```sh
xcodebuild -project Examples/AppAttestVerifyDemo/AppAttestVerifyDemo.xcodeproj \
  -scheme AppAttestVerifyDemo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Verify Attestation

```swift
let verifier = try AppAttestVerifier()
let request = AttestationVerificationRequest(
    attestationObject: attestationCBOR,
    rawChallenge: Data(serverChallenge.utf8),
    teamId: "TEAMID1234",
    bundleId: "com.example.app",
    environment: .production
)

let result = try await verifier.verifyAttestation(request)
let state = VerifiedAttestationState(request: request, result: result)
```

Use the direct `clientDataHash` initializer when you already have the exact
bytes passed to `DCAppAttestService.attestKey`.

## Verify Assertion

```swift
let request = AssertionVerificationRequest(
    assertionObject: assertionCBOR,
    clientData: clientData,
    state: state
)

let result = try await verifier.verifyAssertion(request)
let updatedState = state.updating(with: result)
```

The default assertion flow uses a strict counter policy:
`counter > state.lastCounter`.

## Regenerate The XCFramework

Run this any time the Rust FFI wrapper or the pinned Rust verifier changes:

```sh
Scripts/build-xcframework.sh
```

The script rebuilds the Rust static libraries for iOS device, iOS simulator,
and macOS, then replaces `Frameworks/AppAttestVerifierFFI.xcframework`.

## Package A GitHub Release Binary

To publish a prebuilt binary for SwiftPM consumers, build a release archive:

```sh
Scripts/package-release-binary.sh v0.1.0 TAP-NAP/AppAttestVerifyKit
```

Add `--update-package` when preparing the SwiftPM release tag:

```sh
Scripts/package-release-binary.sh v0.1.0 TAP-NAP/AppAttestVerifyKit --update-package
```

That option replaces `Package.swift` with a release manifest that points the
`AppAttestVerifierFFI` binary target at the generated GitHub Release URL and
checksum. Commit that `Package.swift` change before creating the tag.

The release artifact is a zip file because SwiftPM remote binary targets expect
a zipped XCFramework artifact.

The script rebuilds the local XCFramework, creates:

```text
.release/AppAttestVerifierFFI.xcframework.zip
.release/AppAttestVerifierFFI.xcframework.zip.checksum
.release/AppAttestVerifierFFI.binaryTarget.swift
```

Upload the zip file to the matching GitHub Release:

```sh
git add Package.swift
git commit -m "Use release binary target for v0.1.0"

git tag v0.1.0
git push origin main
git push origin v0.1.0

gh release create v0.1.0 \
  .release/AppAttestVerifierFFI.xcframework.zip \
  --title "v0.1.0" \
  --notes "Rust-backed App Attest verifier binary"
```

## Example App

Open or build after generating the local XCFramework:

```sh
xcodebuild -project Examples/AppAttestVerifyDemo/AppAttestVerifyDemo.xcodeproj \
  -scheme AppAttestVerifyDemo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The app has two flows:

- Attestation: enter Team ID, Bundle ID, raw challenge, choose attestation CBOR,
  and verify. Success saves state in Application Support.
- Assertion: choose assertion CBOR and clientData, verify against saved state,
  and update the saved counter.
