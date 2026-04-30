import Foundation

/// Apple uses different AAGUID values for development and production App
/// Attest objects. This value is forwarded to the Rust verifier.
public enum AppAttestEnvironment: String, Codable, Hashable, Sendable, CaseIterable {
    case production
    case development
}

/// Policy applied to the assertion counter after signature and App ID checks.
public enum AssertionCounterPolicy: Hashable, Sendable {
    case strict(previousCounter: UInt32)
    case positive
    case unchecked

    var rustValue: String {
        switch self {
        case .strict:
            return "strict"
        case .positive:
            return "positive"
        case .unchecked:
            return "unchecked"
        }
    }

    var previousCounter: UInt32? {
        switch self {
        case .strict(let previousCounter):
            return previousCounter
        case .positive, .unchecked:
            return nil
        }
    }
}

/// Input for attestation verification.
///
/// Most callers should use the raw challenge initializer: it mirrors the iOS
/// App Attest flow by hashing the server challenge before Rust verifies the
/// CBOR attestation object. The direct `clientDataHash` initializer exists for
/// fixtures and advanced protocols that already store the hash bytes.
public struct AttestationVerificationRequest: Hashable, Sendable {
    public let attestationObject: Data
    public let clientDataHash: Data
    public let teamId: String
    public let bundleId: String
    public let environment: AppAttestEnvironment
    public let rootAnchor: Data?
    public let inputCheck: Bool
    public let verificationTime: Date?
    public let challengeDebugDescription: String?

    public init(
        attestationObject: Data,
        rawChallenge: Data,
        teamId: String,
        bundleId: String,
        environment: AppAttestEnvironment = .production,
        rootAnchor: Data? = nil,
        inputCheck: Bool = true,
        verificationTime: Date? = nil,
        challengeDebugDescription: String? = nil
    ) {
        self.init(
            attestationObject: attestationObject,
            clientDataHash: Data.appAttestSHA256(rawChallenge),
            teamId: teamId,
            bundleId: bundleId,
            environment: environment,
            rootAnchor: rootAnchor,
            inputCheck: inputCheck,
            verificationTime: verificationTime,
            challengeDebugDescription: challengeDebugDescription
        )
    }

    public init(
        attestationObject: Data,
        clientDataHash: Data,
        teamId: String,
        bundleId: String,
        environment: AppAttestEnvironment = .production,
        rootAnchor: Data? = nil,
        inputCheck: Bool = true,
        verificationTime: Date? = nil,
        challengeDebugDescription: String? = nil
    ) {
        self.attestationObject = attestationObject
        self.clientDataHash = clientDataHash
        self.teamId = teamId
        self.bundleId = bundleId
        self.environment = environment
        self.rootAnchor = rootAnchor
        self.inputCheck = inputCheck
        self.verificationTime = verificationTime
        self.challengeDebugDescription = challengeDebugDescription
    }
}

/// Verified fields extracted from the attestation object and certificate chain.
///
/// These are the values the assertion flow needs later, especially the X9.62
/// public key and the last accepted assertion counter.
public struct AttestationVerificationResult: Codable, Hashable, Sendable {
    public let receiptRaw: Data
    public let authDataRaw: Data
    public let rpIdHash: Data
    public let counter: UInt32
    public let aaguid: Data
    public let credentialId: Data
    public let credentialPublicKeyCOSE: Data
    public let credentialPublicKeyX962: Data
    public let publicKeyX962: Data
    public let publicKeySHA256: Data
    public let appleExtensionRawDER: Data
    public let appleExtensionNonce: Data
    public let rawJSON: String
}

/// Input for assertion verification.
///
/// `clientData` must be the exact raw bytes used by the app before it called
/// `DCAppAttestService.generateAssertion`; the Rust verifier computes
/// `SHA256(clientData)` internally.
public struct AssertionVerificationRequest: Hashable, Sendable {
    public let assertionObject: Data
    public let clientData: Data
    public let publicKeyX962: Data
    public let teamId: String
    public let bundleId: String
    public let counterPolicy: AssertionCounterPolicy

    public init(
        assertionObject: Data,
        clientData: Data,
        publicKeyX962: Data,
        teamId: String,
        bundleId: String,
        counterPolicy: AssertionCounterPolicy
    ) {
        self.assertionObject = assertionObject
        self.clientData = clientData
        self.publicKeyX962 = publicKeyX962
        self.teamId = teamId
        self.bundleId = bundleId
        self.counterPolicy = counterPolicy
    }

    public init(
        assertionObject: Data,
        clientData: Data,
        state: VerifiedAttestationState,
        counterPolicy: AssertionCounterPolicy? = nil
    ) {
        self.init(
            assertionObject: assertionObject,
            clientData: clientData,
            publicKeyX962: state.publicKeyX962,
            teamId: state.teamId,
            bundleId: state.bundleId,
            counterPolicy: counterPolicy ?? .strict(previousCounter: state.lastCounter)
        )
    }
}

/// Parsed assertion verification output. The returned counter should be saved
/// after the caller accepts the protected operation.
public struct AssertionVerificationResult: Codable, Hashable, Sendable {
    public let signatureDER: Data
    public let authenticatorDataRaw: Data
    public let rpIdHash: Data
    public let flags: UInt8
    public let counter: UInt32
    public let rawJSON: String
}
