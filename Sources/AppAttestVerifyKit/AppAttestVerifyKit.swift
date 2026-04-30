import Foundation

/// Public marker for the package.
///
/// The real API surface lives in the focused files next to this one:
/// models describe the App Attest verification inputs and outputs, the verifier
/// calls the Rust core, and the store persists verified state for assertions.
public enum AppAttestVerifyKit {
    public static let rustVerifierRevision = "f93e42f83d1f52cfd3bc41678713f424d30fc921"
}
