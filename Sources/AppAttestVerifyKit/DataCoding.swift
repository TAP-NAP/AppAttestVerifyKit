import CryptoKit
import Foundation

extension Data {
    /// Encodes binary fields for the JSON request that crosses the Swift/Rust
    /// FFI boundary. The Rust wrapper expects standard Base64, not Base64URL.
    var appAttestStandardBase64: String {
        base64EncodedString()
    }

    /// Converts bytes into lowercase hex for debug output and stable state IDs.
    var appAttestHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes the Rust verifier's success JSON fields, which are serialized as
    /// hex strings by the Rust crate.
    init(appAttestHexString hex: String) throws {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count.isMultiple(of: 2) else {
            throw AppAttestVerificationError.invalidFFIResponse("Hex field has an odd number of characters.")
        }

        var bytes = Data()
        bytes.reserveCapacity(cleaned.count / 2)

        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            let pair = cleaned[index..<next]
            guard let byte = UInt8(pair, radix: 16) else {
                throw AppAttestVerificationError.invalidFFIResponse("Hex field contains a non-hex byte.")
            }
            bytes.append(byte)
            index = next
        }

        self = bytes
    }

    static func appAttestSHA256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
