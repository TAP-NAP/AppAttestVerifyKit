import Foundation

/// Storage boundary for verifier state.
///
/// Keeping this as a protocol makes the example app and tests inject their own
/// storage location without changing verification logic.
public protocol AppAttestVerificationStateStore: Sendable {
    func loadState() async throws -> VerifiedAttestationState?
    func saveState(_ state: VerifiedAttestationState) async throws
    func deleteState() async throws
}

/// JSON file store under Application Support.
///
/// This is intentionally transparent storage for a verifier/debug example. A
/// production server would normally store this state in its own database.
public actor ApplicationSupportAttestationStateStore: AppAttestVerificationStateStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directoryURL: URL? = nil,
        filename: String = "VerifiedAttestationState.json"
    ) throws {
        let directoryURL = try directoryURL ?? Self.defaultDirectoryURL()
        self.fileURL = directoryURL.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadState() async throws -> VerifiedAttestationState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return try decoder.decode(VerifiedAttestationState.self, from: Data(contentsOf: fileURL))
    }

    public func saveState(_ state: VerifiedAttestationState) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(state).write(to: fileURL, options: [.atomic])
    }

    public func deleteState() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    public func stateFileURL() -> URL {
        fileURL
    }

    private static func defaultDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleId = Bundle.main.bundleIdentifier ?? "AppAttestVerifyKit"
        return baseURL
            .appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("AppAttestVerifyKit", isDirectory: true)
    }
}
