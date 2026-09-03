import Foundation

struct KDFParameters: Codable, Equatable, Sendable {
    static let supportedAlgorithm = "PBKDF2-HMAC-SHA256"

    var algorithm: String
    var salt: Data
    var iterations: Int
}

struct SealedValue: Codable, Equatable, Sendable {
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}

struct VaultEnvelope: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var vaultID: UUID
    var kdf: KDFParameters
    var wrappedDEK: SealedValue
    var payload: SealedValue
}

enum VaultCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64
        return decoder
    }

    static func encode(_ envelope: VaultEnvelope) throws -> Data {
        try encoder().encode(envelope)
    }

    static func decodeEnvelope(from data: Data) throws -> VaultEnvelope {
        try decoder().decode(VaultEnvelope.self, from: data)
    }
}
