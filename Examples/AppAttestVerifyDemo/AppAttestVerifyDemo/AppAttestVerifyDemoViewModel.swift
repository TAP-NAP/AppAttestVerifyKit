import AppAttestVerifyKit
import Foundation

enum AppAttestVerifyImportTarget: Identifiable {
    case attestationObject
    case rootAnchor
    case assertionObject
    case clientData

    var id: String {
        switch self {
        case .attestationObject: "attestationObject"
        case .rootAnchor: "rootAnchor"
        case .assertionObject: "assertionObject"
        case .clientData: "clientData"
        }
    }
}

enum AppAttestVerifyCounterPolicyMode: String, CaseIterable, Identifiable {
    case strict
    case positive
    case unchecked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict: "Strict"
        case .positive: "Positive"
        case .unchecked: "Unchecked"
        }
    }
}

@MainActor
final class AppAttestVerifyDemoViewModel: ObservableObject {
    @Published var teamId = "UD3269PSCB"
    @Published var bundleId = "com.appattestkit.AppAttestDemo"
    @Published var environment: AppAttestEnvironment = .development
    @Published var rawChallenge = "nearbycommunity0123"
    @Published var verificationTimeUnixSeconds = ""
    @Published var inputCheckEnabled = true

    @Published private(set) var attestationObject: Data?
    @Published private(set) var attestationFileName = "None"
    @Published private(set) var rootAnchorOverride: Data?
    @Published private(set) var rootAnchorFileName = "Bundled Apple Root CA"

    @Published private(set) var assertionObject: Data?
    @Published private(set) var assertionFileName = "None"
    @Published private(set) var clientDataFromFile: Data?
    @Published private(set) var clientDataFileName = "Text input"
    @Published var clientDataText = #"{"request_challenge":"challenge-1","operation":"test"}"#
    @Published var counterPolicyMode: AppAttestVerifyCounterPolicyMode = .strict

    @Published private(set) var storedState: VerifiedAttestationState?
    @Published private(set) var isWorking = false
    @Published var statusText = "Choose an attestation CBOR file, enter App Attest context, then verify."
    @Published var debugText = ""

    private let verifier: any AppAttestVerificationClient
    private let store: ApplicationSupportAttestationStateStore

    init() {
        var resolvedVerifier: any AppAttestVerificationClient
        var resolvedStore: ApplicationSupportAttestationStateStore
        var resolvedStatus: String?

        do {
            resolvedVerifier = try AppAttestVerifier()
            resolvedStore = try ApplicationSupportAttestationStateStore()
            resolvedStatus = nil
        } catch {
            resolvedVerifier = UnavailableAppAttestVerificationClient(initializationError: error)
            resolvedStore = try! ApplicationSupportAttestationStateStore(
                directoryURL: FileManager.default.temporaryDirectory
            )
            resolvedStatus = "Initialization failed: \(error.localizedDescription)"
        }

        self.verifier = resolvedVerifier
        self.store = resolvedStore
        if let resolvedStatus {
            self.statusText = resolvedStatus
        }
    }

    var storedStateSummary: String {
        guard let storedState else {
            return "No verified attestation state saved yet."
        }

        return """
        teamId: \(storedState.teamId)
        bundleId: \(storedState.bundleId)
        environment: \(storedState.environment.rawValue)
        credentialId: \(storedState.credentialId.appAttestPreviewHex)
        publicKeySHA256: \(storedState.publicKeySHA256.appAttestPreviewHex)
        lastCounter: \(storedState.lastCounter)
        updatedAt: \(storedState.updatedAt)
        """
    }

    func loadStoredState() async {
        do {
            storedState = try await store.loadState()
            if let storedState {
                statusText = "Loaded saved attestation state.\n\(storedState.bundleId)"
                debugText = storedStateSummary
            }
        } catch {
            statusText = "Load stored state failed.\n\(error.localizedDescription)"
        }
    }

    func handleFileImport(_ result: Result<[URL], any Error>, target: AppAttestVerifyImportTarget?) {
        guard let target else {
            statusText = "Import failed.\nThe app lost track of which file role was being selected."
            return
        }

        do {
            let url = try result.get().first.unwrapFileURL()
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            applyImportedData(data, filename: url.lastPathComponent, target: target)
        } catch {
            statusText = "Import failed.\n\(error.localizedDescription)"
        }
    }

    func verifyAttestation() {
        guard let attestationObject else {
            statusText = "Choose an attestation CBOR file first."
            return
        }

        run("Verify attestation") {
            let request = try self.makeAttestationRequest(attestationObject: attestationObject)
            let result = try await self.verifier.verifyAttestation(request)
            let state = VerifiedAttestationState(request: request, result: result)
            try await self.store.saveState(state)

            self.storedState = state
            self.statusText = """
            Attestation verified and saved.
            credentialId: \(state.credentialId.appAttestPreviewHex)
            publicKeySHA256: \(state.publicKeySHA256.appAttestPreviewHex)
            """
            self.debugText = result.rawJSON
        }
    }

    func verifyAssertion() {
        guard let storedState else {
            statusText = "Verify attestation before verifying assertions."
            return
        }
        guard let assertionObject else {
            statusText = "Choose an assertion CBOR file first."
            return
        }

        run("Verify assertion") {
            let request = AssertionVerificationRequest(
                assertionObject: assertionObject,
                clientData: self.currentClientData(),
                state: storedState,
                counterPolicy: self.counterPolicy(for: storedState)
            )
            let result = try await self.verifier.verifyAssertion(request)
            let updatedState = storedState.updating(with: result)
            try await self.store.saveState(updatedState)

            self.storedState = updatedState
            self.statusText = """
            Assertion verified and counter saved.
            counter: \(result.counter)
            """
            self.debugText = result.rawJSON
        }
    }

    func clearStoredState() {
        run("Clear stored state") {
            try await self.store.deleteState()
            self.storedState = nil
            self.statusText = "Stored attestation state cleared."
            self.debugText = ""
        }
    }

    private func applyImportedData(_ data: Data, filename: String, target: AppAttestVerifyImportTarget) {
        switch target {
        case .attestationObject:
            attestationObject = data
            attestationFileName = filename
        case .rootAnchor:
            rootAnchorOverride = data
            rootAnchorFileName = filename
        case .assertionObject:
            assertionObject = data
            assertionFileName = filename
        case .clientData:
            clientDataFromFile = data
            clientDataFileName = filename
            clientDataText = String(data: data, encoding: .utf8) ?? clientDataText
        }

        statusText = "Loaded \(filename)."
    }

    private func makeAttestationRequest(attestationObject: Data) throws -> AttestationVerificationRequest {
        let cleanedTeamId = teamId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBundleId = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedChallenge = rawChallenge.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedTeamId.isEmpty else {
            throw AppAttestVerificationError.invalidInput("Team ID is required.")
        }
        guard !cleanedBundleId.isEmpty else {
            throw AppAttestVerificationError.invalidInput("Bundle ID is required.")
        }
        guard !cleanedChallenge.isEmpty else {
            throw AppAttestVerificationError.invalidInput("Raw challenge is required.")
        }

        return AttestationVerificationRequest(
            attestationObject: attestationObject,
            rawChallenge: Data(cleanedChallenge.utf8),
            teamId: cleanedTeamId,
            bundleId: cleanedBundleId,
            environment: environment,
            rootAnchor: rootAnchorOverride,
            inputCheck: inputCheckEnabled,
            verificationTime: parsedVerificationTime(),
            challengeDebugDescription: cleanedChallenge
        )
    }

    private func parsedVerificationTime() -> Date? {
        let cleaned = verificationTimeUnixSeconds.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let seconds = TimeInterval(cleaned) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private func currentClientData() -> Data {
        clientDataFromFile ?? Data(clientDataText.utf8)
    }

    private func counterPolicy(for state: VerifiedAttestationState) -> AssertionCounterPolicy {
        switch counterPolicyMode {
        case .strict:
            return .strict(previousCounter: state.lastCounter)
        case .positive:
            return .positive
        case .unchecked:
            return .unchecked
        }
    }

    private func run(_ label: String, operation: @escaping () async throws -> Void) {
        isWorking = true
        statusText = "\(label)..."

        Task {
            do {
                try await operation()
            } catch {
                self.statusText = "\(label) failed.\n\(error.localizedDescription)"
                self.debugText = "\(error)"
            }
            self.isWorking = false
        }
    }
}

/// Demo-only replacement used when the generated Rust XCFramework is absent.
///
/// It lets the UI and debug panel launch from a clean checkout, then surfaces a
/// precise build instruction when the user taps Verify before generating the
/// local binary.
private actor UnavailableAppAttestVerificationClient: AppAttestVerificationClient {
    private let message: String

    init(initializationError: any Error) {
        self.message = initializationError.localizedDescription
    }

    func verifyAttestation(_ request: AttestationVerificationRequest) async throws -> AttestationVerificationResult {
        throw AppAttestVerificationError.missingResource(message)
    }

    func verifyAssertion(_ request: AssertionVerificationRequest) async throws -> AssertionVerificationResult {
        throw AppAttestVerificationError.missingResource(message)
    }
}

private extension Optional where Wrapped == URL {
    func unwrapFileURL() throws -> URL {
        guard let self else {
            throw AppAttestVerificationError.invalidInput("No file was selected.")
        }
        return self
    }
}

private extension Data {
    var appAttestPreviewHex: String {
        let prefix = self.prefix(16).map { String(format: "%02x", $0) }.joined()
        return count > 16 ? "\(prefix)..." : prefix
    }
}
