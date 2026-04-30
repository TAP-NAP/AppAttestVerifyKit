import Foundation

/// Persisted state created after attestation succeeds and consumed by later
/// assertion verification. None of these values are secrets; they are kept in
/// Application Support so the example app can display and inspect them.
public struct VerifiedAttestationState: Codable, Hashable, Sendable {
    public let teamId: String
    public let bundleId: String
    public let environment: AppAttestEnvironment
    public let credentialId: Data
    public let publicKeyX962: Data
    public let publicKeySHA256: Data
    public let receiptRaw: Data
    public let attestationObjectSHA256: Data
    public let clientDataHash: Data
    public let challengeDebugDescription: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let lastCounter: UInt32
    public let lastAttestationResultJSON: String
    public let lastAssertionResultJSON: String?

    public init(
        teamId: String,
        bundleId: String,
        environment: AppAttestEnvironment,
        credentialId: Data,
        publicKeyX962: Data,
        publicKeySHA256: Data,
        receiptRaw: Data,
        attestationObjectSHA256: Data,
        clientDataHash: Data,
        challengeDebugDescription: String?,
        createdAt: Date,
        updatedAt: Date,
        lastCounter: UInt32,
        lastAttestationResultJSON: String,
        lastAssertionResultJSON: String?
    ) {
        self.teamId = teamId
        self.bundleId = bundleId
        self.environment = environment
        self.credentialId = credentialId
        self.publicKeyX962 = publicKeyX962
        self.publicKeySHA256 = publicKeySHA256
        self.receiptRaw = receiptRaw
        self.attestationObjectSHA256 = attestationObjectSHA256
        self.clientDataHash = clientDataHash
        self.challengeDebugDescription = challengeDebugDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCounter = lastCounter
        self.lastAttestationResultJSON = lastAttestationResultJSON
        self.lastAssertionResultJSON = lastAssertionResultJSON
    }

    public init(
        request: AttestationVerificationRequest,
        result: AttestationVerificationResult,
        now: Date = Date()
    ) {
        self.init(
            teamId: request.teamId,
            bundleId: request.bundleId,
            environment: request.environment,
            credentialId: result.credentialId,
            publicKeyX962: result.publicKeyX962,
            publicKeySHA256: result.publicKeySHA256,
            receiptRaw: result.receiptRaw,
            attestationObjectSHA256: Data.appAttestSHA256(request.attestationObject),
            clientDataHash: request.clientDataHash,
            challengeDebugDescription: request.challengeDebugDescription,
            createdAt: now,
            updatedAt: now,
            lastCounter: result.counter,
            lastAttestationResultJSON: result.rawJSON,
            lastAssertionResultJSON: nil
        )
    }

    public func updating(with result: AssertionVerificationResult, now: Date = Date()) -> Self {
        Self(
            teamId: teamId,
            bundleId: bundleId,
            environment: environment,
            credentialId: credentialId,
            publicKeyX962: publicKeyX962,
            publicKeySHA256: publicKeySHA256,
            receiptRaw: receiptRaw,
            attestationObjectSHA256: attestationObjectSHA256,
            clientDataHash: clientDataHash,
            challengeDebugDescription: challengeDebugDescription,
            createdAt: createdAt,
            updatedAt: now,
            lastCounter: result.counter,
            lastAttestationResultJSON: lastAttestationResultJSON,
            lastAssertionResultJSON: result.rawJSON
        )
    }
}
