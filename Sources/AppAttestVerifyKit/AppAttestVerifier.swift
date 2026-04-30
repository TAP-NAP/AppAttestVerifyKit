import Foundation

#if canImport(AppAttestVerifierFFI)
import AppAttestVerifierFFI
#endif

/// High-level Swift API for the Rust-backed App Attest verifier.
public protocol AppAttestVerificationClient: Sendable {
    func verifyAttestation(_ request: AttestationVerificationRequest) async throws -> AttestationVerificationResult
    func verifyAssertion(_ request: AssertionVerificationRequest) async throws -> AssertionVerificationResult
}

#if canImport(AppAttestVerifierFFI)
/// Stateless wrapper around the Rust verifier.
///
/// Each call creates a small JSON request, passes it through the C ABI, copies
/// the returned JSON, then immediately frees the Rust-owned buffer.
public actor AppAttestVerifier: AppAttestVerificationClient {
    private let defaultRootAnchor: Data
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaultRootAnchor: Data? = nil) throws {
        self.defaultRootAnchor = try defaultRootAnchor ?? AppAttestTrustAnchor.defaultAppleAppAttestationRootCA()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    public func verifyAttestation(_ request: AttestationVerificationRequest) async throws -> AttestationVerificationResult {
        let rustRequest = RustAttestationRequest(
            attestationObjectBase64: request.attestationObject.appAttestStandardBase64,
            rootAnchorBase64: (request.rootAnchor ?? defaultRootAnchor).appAttestStandardBase64,
            clientDataHashBase64: request.clientDataHash.appAttestStandardBase64,
            teamId: request.teamId,
            bundleId: request.bundleId,
            environment: request.environment.rawValue,
            inputCheck: request.inputCheck,
            verificationTimeUnixSeconds: request.verificationTime.map { UInt64($0.timeIntervalSince1970) }
        )
        let responseData = try callRust(
            request: rustRequest,
            function: app_attest_verifier_verify_attestation
        )
        let envelope = try decoder.decode(FFIEnvelope<RustAttestationSuccess>.self, from: responseData)
        let rawJSON = try rawValueJSON(from: responseData)
        return try envelope.unwrap().swiftResult(rawJSON: rawJSON)
    }

    public func verifyAssertion(_ request: AssertionVerificationRequest) async throws -> AssertionVerificationResult {
        let rustRequest = RustAssertionRequest(
            assertionObjectBase64: request.assertionObject.appAttestStandardBase64,
            clientDataBase64: request.clientData.appAttestStandardBase64,
            publicKeyX962Base64: request.publicKeyX962.appAttestStandardBase64,
            teamId: request.teamId,
            bundleId: request.bundleId,
            counterPolicy: request.counterPolicy.rustValue,
            previousCounter: request.counterPolicy.previousCounter
        )
        let responseData = try callRust(
            request: rustRequest,
            function: app_attest_verifier_verify_assertion
        )
        let envelope = try decoder.decode(FFIEnvelope<RustAssertionSuccess>.self, from: responseData)
        let rawJSON = try rawValueJSON(from: responseData)
        return try envelope.unwrap().swiftResult(rawJSON: rawJSON)
    }

    private func callRust<Request: Encodable>(
        request: Request,
        function: (UnsafePointer<UInt8>?, UInt) -> AppAttestVerifierFFIBuffer
    ) throws -> Data {
        let requestData = try encoder.encode(request)
        let buffer = requestData.withUnsafeBytes { rawBuffer in
            function(rawBuffer.bindMemory(to: UInt8.self).baseAddress, UInt(requestData.count))
        }
        defer {
            app_attest_verifier_free_buffer(buffer)
        }

        guard let pointer = buffer.ptr, buffer.len > 0 else {
            throw AppAttestVerificationError.invalidFFIResponse("Rust returned an empty response buffer.")
        }

        return Data(bytes: pointer, count: Int(buffer.len))
    }

    private func rawValueJSON(from responseData: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: responseData)
        guard
            let dictionary = object as? [String: Any],
            let value = dictionary["value"],
            JSONSerialization.isValidJSONObject(value)
        else {
            return String(data: responseData, encoding: .utf8) ?? "{}"
        }

        let valueData = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(data: valueData, encoding: .utf8) ?? "{}"
    }
}
#else
/// Placeholder client compiled when the local Rust XCFramework has not been generated yet.
///
/// This keeps the Swift package loadable from a fresh clone, while every real
/// verification call still fails clearly until the developer runs the build
/// script that creates Frameworks/AppAttestVerifierFFI.xcframework.
public actor AppAttestVerifier: AppAttestVerificationClient {
    private static let missingBinaryMessage = """
    Rust verifier binary is missing. Run Scripts/build-xcframework.sh before using AppAttestVerifier.
    """

    public init(defaultRootAnchor: Data? = nil) throws {
        throw AppAttestVerificationError.missingResource(Self.missingBinaryMessage)
    }

    public func verifyAttestation(_ request: AttestationVerificationRequest) async throws -> AttestationVerificationResult {
        throw AppAttestVerificationError.missingResource(Self.missingBinaryMessage)
    }

    public func verifyAssertion(_ request: AssertionVerificationRequest) async throws -> AssertionVerificationResult {
        throw AppAttestVerificationError.missingResource(Self.missingBinaryMessage)
    }
}
#endif

private struct FFIEnvelope<Value: Decodable>: Decodable {
    let ok: Bool
    let value: Value?
    let error: StructuredVerificationError?

    func unwrap() throws -> Value {
        if ok, let value {
            return value
        }
        if let error {
            throw AppAttestVerificationError.rust(error)
        }
        throw AppAttestVerificationError.invalidFFIResponse("Rust response had neither value nor error.")
    }
}

private struct RustAttestationRequest: Encodable {
    let attestationObjectBase64: String
    let rootAnchorBase64: String
    let clientDataHashBase64: String
    let teamId: String
    let bundleId: String
    let environment: String
    let inputCheck: Bool
    let verificationTimeUnixSeconds: UInt64?

    private enum CodingKeys: String, CodingKey {
        case attestationObjectBase64 = "attestation_object_base64"
        case rootAnchorBase64 = "root_anchor_base64"
        case clientDataHashBase64 = "client_data_hash_base64"
        case teamId = "team_id"
        case bundleId = "bundle_id"
        case environment
        case inputCheck = "input_check"
        case verificationTimeUnixSeconds = "verification_time_unix_seconds"
    }
}

private struct RustAssertionRequest: Encodable {
    let assertionObjectBase64: String
    let clientDataBase64: String
    let publicKeyX962Base64: String
    let teamId: String
    let bundleId: String
    let counterPolicy: String
    let previousCounter: UInt32?

    private enum CodingKeys: String, CodingKey {
        case assertionObjectBase64 = "assertion_object_base64"
        case clientDataBase64 = "client_data_base64"
        case publicKeyX962Base64 = "public_key_x962_base64"
        case teamId = "team_id"
        case bundleId = "bundle_id"
        case counterPolicy = "counter_policy"
        case previousCounter = "previous_counter"
    }
}

private struct RustAttestationSuccess: Decodable {
    let receiptRaw: String
    let parsedAuthData: RustParsedAuthData
    let firstCertificateValues: RustFirstCertificateValues

    private enum CodingKeys: String, CodingKey {
        case receiptRaw = "receipt_raw"
        case parsedAuthData = "parsed_auth_data"
        case firstCertificateValues = "first_certificate_values"
    }

    func swiftResult(rawJSON: String) throws -> AttestationVerificationResult {
        AttestationVerificationResult(
            receiptRaw: try Data(appAttestHexString: receiptRaw),
            authDataRaw: try Data(appAttestHexString: parsedAuthData.authDataRaw),
            rpIdHash: try Data(appAttestHexString: parsedAuthData.rpIdHash),
            counter: parsedAuthData.counter,
            aaguid: try Data(appAttestHexString: parsedAuthData.aaguid),
            credentialId: try Data(appAttestHexString: parsedAuthData.credentialId),
            credentialPublicKeyCOSE: try Data(appAttestHexString: parsedAuthData.credentialPublicKeyCOSE),
            credentialPublicKeyX962: try Data(appAttestHexString: parsedAuthData.credentialPublicKeyX962),
            publicKeyX962: try Data(appAttestHexString: firstCertificateValues.publicKeyX962),
            publicKeySHA256: try Data(appAttestHexString: firstCertificateValues.publicKeySHA256),
            appleExtensionRawDER: try Data(appAttestHexString: firstCertificateValues.appleExtensionRawDER),
            appleExtensionNonce: try Data(appAttestHexString: firstCertificateValues.appleExtensionNonce),
            rawJSON: rawJSON
        )
    }
}

private struct RustParsedAuthData: Decodable {
    let authDataRaw: String
    let rpIdHash: String
    let counter: UInt32
    let aaguid: String
    let credentialId: String
    let credentialPublicKeyCOSE: String
    let credentialPublicKeyX962: String

    private enum CodingKeys: String, CodingKey {
        case authDataRaw = "auth_data_raw"
        case rpIdHash = "rp_id_hash"
        case counter
        case aaguid
        case credentialId = "credential_id"
        case credentialPublicKeyCOSE = "credential_public_key_cose"
        case credentialPublicKeyX962 = "credential_public_key_x962"
    }
}

private struct RustFirstCertificateValues: Decodable {
    let publicKeyX962: String
    let publicKeySHA256: String
    let appleExtensionRawDER: String
    let appleExtensionNonce: String

    private enum CodingKeys: String, CodingKey {
        case publicKeyX962 = "public_key_x962"
        case publicKeySHA256 = "public_key_sha256"
        case appleExtensionRawDER = "apple_extension_raw_der"
        case appleExtensionNonce = "apple_extension_nonce"
    }
}

private struct RustAssertionSuccess: Decodable {
    let parsedAssertion: RustParsedAssertion
    let parsedAuthenticatorData: RustParsedAssertionAuthenticatorData
    let counter: UInt32

    private enum CodingKeys: String, CodingKey {
        case parsedAssertion = "parsed_assertion"
        case parsedAuthenticatorData = "parsed_authenticator_data"
        case counter
    }

    func swiftResult(rawJSON: String) throws -> AssertionVerificationResult {
        AssertionVerificationResult(
            signatureDER: try Data(appAttestHexString: parsedAssertion.signatureDER),
            authenticatorDataRaw: try Data(appAttestHexString: parsedAuthenticatorData.authenticatorDataRaw),
            rpIdHash: try Data(appAttestHexString: parsedAuthenticatorData.rpIdHash),
            flags: parsedAuthenticatorData.flags,
            counter: counter,
            rawJSON: rawJSON
        )
    }
}

private struct RustParsedAssertion: Decodable {
    let signatureDER: String
    let authenticatorDataRaw: String

    private enum CodingKeys: String, CodingKey {
        case signatureDER = "signature_der"
        case authenticatorDataRaw = "authenticator_data_raw"
    }
}

private struct RustParsedAssertionAuthenticatorData: Decodable {
    let authenticatorDataRaw: String
    let rpIdHash: String
    let flags: UInt8
    let counter: UInt32

    private enum CodingKeys: String, CodingKey {
        case authenticatorDataRaw = "authenticator_data_raw"
        case rpIdHash = "rp_id_hash"
        case flags
        case counter
    }
}
