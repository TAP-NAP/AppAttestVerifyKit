import CryptoKit
import Foundation
import Testing
@testable import AppAttestVerifyKit

private let sampleVerificationTime = Date(timeIntervalSince1970: 1_713_456_894)

@Test func attestationVerificationAcceptsOfficialFixture() async throws {
    let verifier = try AppAttestVerifier(defaultRootAnchor: fixtureData("anchors/apple_app_attestation_root_ca", "pem"))
    let request = AttestationVerificationRequest(
        attestationObject: try fixtureData("positive/apple_attestation_object", "cbor"),
        clientDataHash: Data("test_server_challenge".utf8),
        teamId: "0352187391",
        bundleId: "com.apple.example_app_attest",
        environment: .production,
        verificationTime: sampleVerificationTime,
        challengeDebugDescription: "official fixture clientDataHash"
    )

    let result = try await verifier.verifyAttestation(request)

    #expect(!result.receiptRaw.isEmpty)
    #expect(!result.publicKeyX962.isEmpty)
    #expect(result.counter == 0)
}

@Test func attestationVerificationRejectsWrongAppId() async throws {
    let verifier = try AppAttestVerifier(defaultRootAnchor: fixtureData("anchors/apple_app_attestation_root_ca", "pem"))
    let request = AttestationVerificationRequest(
        attestationObject: try fixtureData("positive/apple_attestation_object", "cbor"),
        clientDataHash: Data("test_server_challenge".utf8),
        teamId: "0352187391",
        bundleId: "com.example.wrong",
        environment: .production,
        verificationTime: sampleVerificationTime
    )

    await #expect(throws: AppAttestVerificationError.self) {
        _ = try await verifier.verifyAttestation(request)
    }
}

@Test func assertionVerificationAcceptsGeneratedFixture() async throws {
    let verifier = try AppAttestVerifier()
    let fixture = try AssertionFixture(counter: 7)
    let request = AssertionVerificationRequest(
        assertionObject: fixture.assertionObject,
        clientData: fixture.clientData,
        publicKeyX962: fixture.publicKeyX962,
        teamId: fixture.teamId,
        bundleId: fixture.bundleId,
        counterPolicy: .strict(previousCounter: 0)
    )

    let result = try await verifier.verifyAssertion(request)

    #expect(result.counter == 7)
    #expect(!result.signatureDER.isEmpty)
    #expect(result.authenticatorDataRaw.count == 37)
}

@Test func assertionVerificationRejectsWrongClientData() async throws {
    let verifier = try AppAttestVerifier()
    let fixture = try AssertionFixture(counter: 7)
    let request = AssertionVerificationRequest(
        assertionObject: fixture.assertionObject,
        clientData: Data("wrong client data".utf8),
        publicKeyX962: fixture.publicKeyX962,
        teamId: fixture.teamId,
        bundleId: fixture.bundleId,
        counterPolicy: .unchecked
    )

    await #expect(throws: AppAttestVerificationError.self) {
        _ = try await verifier.verifyAssertion(request)
    }
}

@Test func assertionVerificationRejectsNonIncreasingCounter() async throws {
    let verifier = try AppAttestVerifier()
    let fixture = try AssertionFixture(counter: 7)
    let request = AssertionVerificationRequest(
        assertionObject: fixture.assertionObject,
        clientData: fixture.clientData,
        publicKeyX962: fixture.publicKeyX962,
        teamId: fixture.teamId,
        bundleId: fixture.bundleId,
        counterPolicy: .strict(previousCounter: 7)
    )

    await #expect(throws: AppAttestVerificationError.self) {
        _ = try await verifier.verifyAssertion(request)
    }
}

@Test func applicationSupportStoreSavesLoadsAndDeletesState() async throws {
    let directory = FileManager.default
        .temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = try ApplicationSupportAttestationStateStore(directoryURL: directory)
    let state = VerifiedAttestationState(
        teamId: "TEAMID1234",
        bundleId: "com.example.app",
        environment: .development,
        credentialId: Data([1, 2, 3]),
        publicKeyX962: Data([4, 5, 6]),
        publicKeySHA256: Data([7, 8, 9]),
        receiptRaw: Data([10]),
        attestationObjectSHA256: Data([11]),
        clientDataHash: Data([12]),
        challengeDebugDescription: "unit-test",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20),
        lastCounter: 3,
        lastAttestationResultJSON: "{}",
        lastAssertionResultJSON: nil
    )

    try await store.saveState(state)
    let loaded = try await store.loadState()
    try await store.deleteState()
    let deleted = try await store.loadState()

    #expect(loaded == state)
    #expect(deleted == nil)
}

private func fixtureData(_ name: String, _ extensionName: String) throws -> Data {
    let resourceName = URL(fileURLWithPath: name).lastPathComponent
    guard let url = Bundle.module.url(forResource: resourceName, withExtension: extensionName) else {
        throw AppAttestVerificationError.missingResource("Missing test fixture \(name).\(extensionName)")
    }
    return try Data(contentsOf: url)
}

private struct AssertionFixture {
    let teamId = "UD3269PSCB"
    let bundleId = "com.appattestkit.AppAttestDemo"
    let clientData = Data(#"{"request_challenge":"challenge-1","operation":"test"}"#.utf8)
    let publicKeyX962: Data
    let assertionObject: Data

    init(counter: UInt32) throws {
        let signingKey = P256.Signing.PrivateKey()
        self.publicKeyX962 = signingKey.publicKey.x963Representation

        let authenticatorData = Self.authenticatorData(
            teamId: teamId,
            bundleId: bundleId,
            counter: counter
        )
        let nonce = Self.assertionNonce(
            authenticatorData: authenticatorData,
            clientData: clientData
        )
        let signature = try signingKey.signature(for: nonce)

        self.assertionObject = Self.assertionObject(
            signatureDER: signature.derRepresentation,
            authenticatorData: authenticatorData
        )
    }

    private static func authenticatorData(teamId: String, bundleId: String, counter: UInt32) -> Data {
        var data = Data(SHA256.hash(data: Data("\(teamId).\(bundleId)".utf8)))
        data.append(0)
        data.append(contentsOf: withUnsafeBytes(of: counter.bigEndian, Array.init))
        return data
    }

    private static func assertionNonce(authenticatorData: Data, clientData: Data) -> Data {
        let clientDataHash = Data(SHA256.hash(data: clientData))
        var nonceInput = Data()
        nonceInput.append(authenticatorData)
        nonceInput.append(clientDataHash)
        return Data(SHA256.hash(data: nonceInput))
    }

    private static func assertionObject(signatureDER: Data, authenticatorData: Data) -> Data {
        var data = Data([0xA2])
        data.append(cborText("signature"))
        data.append(cborBytes(signatureDER))
        data.append(cborText("authenticatorData"))
        data.append(cborBytes(authenticatorData))
        return data
    }

    private static func cborText(_ string: String) -> Data {
        var data = cborHeader(major: 3, count: string.utf8.count)
        data.append(contentsOf: string.utf8)
        return data
    }

    private static func cborBytes(_ bytes: Data) -> Data {
        var data = cborHeader(major: 2, count: bytes.count)
        data.append(bytes)
        return data
    }

    private static func cborHeader(major: UInt8, count: Int) -> Data {
        let prefix = major << 5
        switch count {
        case 0..<24:
            return Data([prefix | UInt8(count)])
        case 24...UInt8.max.intValue:
            return Data([prefix | 24, UInt8(count)])
        default:
            return Data([prefix | 25, UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF)])
        }
    }
}

private extension UInt8 {
    var intValue: Int { Int(self) }
}
