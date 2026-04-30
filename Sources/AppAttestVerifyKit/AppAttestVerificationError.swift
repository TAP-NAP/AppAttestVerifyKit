import Foundation

/// Structured Rust validation errors are preserved so callers and the example
/// app can show exactly which App Attest stage rejected the artifact.
public struct StructuredVerificationError: Codable, Error, Hashable, Sendable, LocalizedError {
    public let validationStage: String
    public let errorCode: String
    public let message: String

    public var errorDescription: String? {
        "\(validationStage) \(errorCode): \(message)"
    }

    private enum CodingKeys: String, CodingKey {
        case validationStage = "validation_stage"
        case errorCode = "error_code"
        case message
    }
}

/// Errors added by the Swift wrapper before or after the Rust verifier runs.
public enum AppAttestVerificationError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case missingResource(String)
    case rust(StructuredVerificationError)
    case invalidFFIResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .missingResource(let message):
            return message
        case .rust(let error):
            return error.localizedDescription
        case .invalidFFIResponse(let message):
            return message
        }
    }
}
