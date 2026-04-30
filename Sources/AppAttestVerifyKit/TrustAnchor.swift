import Foundation

/// Loads the Apple App Attestation Root CA bundled with the package.
public enum AppAttestTrustAnchor {
    public static func defaultAppleAppAttestationRootCA() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "apple_app_attestation_root_ca",
            withExtension: "pem"
        ) else {
            throw AppAttestVerificationError.missingResource(
                "The bundled Apple App Attestation Root CA resource is missing."
            )
        }

        return try Data(contentsOf: url)
    }
}
