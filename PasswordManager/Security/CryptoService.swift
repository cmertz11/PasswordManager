import CryptoKit
import Foundation

enum VaultCryptoError: Error, Equatable {
    case unsupportedFormat
    case unsupportedSchema
    case unsupportedKDF
    case malformedEnvelope
    case authenticationFailed
}

struct UnlockedVault: Sendable {
    var payload: VaultPayload
    var keyData: Data
}

enum CryptoService {
    static let vaultKeyByteCount = 32
    private static let nonceByteCount = 12

    static func createVault(
        password: String,
        payload: VaultPayload = VaultPayload(),
        iterations: Int = PasswordKDF.defaultIterations
    ) throws -> (envelope: VaultEnvelope, unlocked: UnlockedVault) {
        let vaultID = UUID()
        let parameters = try PasswordKDF.makeParameters(iterations: iterations)
        var keyEncryptionKey = try PasswordKDF.deriveKey(password: password, parameters: parameters)
        defer { keyEncryptionKey.resetBytes(in: 0..<keyEncryptionKey.count) }
        let vaultKey = try SecureRandom.bytes(count: vaultKeyByteCount)

        let wrappedDEK = try seal(
            vaultKey,
            keyData: keyEncryptionKey,
            authenticatedData: wrapAAD(
                formatVersion: VaultEnvelope.currentFormatVersion,
                vaultID: vaultID,
                parameters: parameters
            )
        )
        let encryptedPayload = try sealPayload(payload, vaultID: vaultID, keyData: vaultKey)

        let envelope = VaultEnvelope(
            formatVersion: VaultEnvelope.currentFormatVersion,
            vaultID: vaultID,
            kdf: parameters,
            wrappedDEK: wrappedDEK,
            payload: encryptedPayload
        )
        return (envelope, UnlockedVault(payload: payload, keyData: vaultKey))
    }

    static func unlock(_ envelope: VaultEnvelope, password: String) throws -> UnlockedVault {
        try validate(envelope)
        var keyEncryptionKey = try PasswordKDF.deriveKey(password: password, parameters: envelope.kdf)
        defer { keyEncryptionKey.resetBytes(in: 0..<keyEncryptionKey.count) }
        let keyData: Data
        do {
            keyData = try open(
                envelope.wrappedDEK,
                keyData: keyEncryptionKey,
                authenticatedData: wrapAAD(
                    formatVersion: envelope.formatVersion,
                    vaultID: envelope.vaultID,
                    parameters: envelope.kdf
                )
            )
        } catch {
            throw VaultCryptoError.authenticationFailed
        }
        guard keyData.count == vaultKeyByteCount else {
            throw VaultCryptoError.malformedEnvelope
        }
        return UnlockedVault(
            payload: try decryptPayload(envelope, keyData: keyData),
            keyData: keyData
        )
    }

    static func unlock(_ envelope: VaultEnvelope, keyData: Data) throws -> UnlockedVault {
        try validate(envelope)
        guard keyData.count == vaultKeyByteCount else {
            throw VaultCryptoError.malformedEnvelope
        }
        return UnlockedVault(
            payload: try decryptPayload(envelope, keyData: keyData),
            keyData: keyData
        )
    }

    static func reseal(
        payload: VaultPayload,
        preserving envelope: VaultEnvelope,
        keyData: Data
    ) throws -> VaultEnvelope {
        try validate(envelope)
        guard keyData.count == vaultKeyByteCount else {
            throw VaultCryptoError.malformedEnvelope
        }
        var updated = envelope
        updated.payload = try sealPayload(payload, vaultID: envelope.vaultID, keyData: keyData)
        return updated
    }

    static func decryptPayload(_ envelope: VaultEnvelope, keyData: Data) throws -> VaultPayload {
        let plaintext: Data
        do {
            plaintext = try open(
                envelope.payload,
                keyData: keyData,
                authenticatedData: payloadAAD(
                    formatVersion: envelope.formatVersion,
                    vaultID: envelope.vaultID
                )
            )
        } catch {
            throw VaultCryptoError.authenticationFailed
        }

        let payload: VaultPayload
        do {
            payload = try VaultCodec.decoder().decode(VaultPayload.self, from: plaintext)
        } catch {
            throw VaultCryptoError.malformedEnvelope
        }
        guard payload.schemaVersion == VaultPayload.currentSchemaVersion else {
            throw VaultCryptoError.unsupportedSchema
        }
        return payload
    }

    private static func sealPayload(_ payload: VaultPayload, vaultID: UUID, keyData: Data) throws -> SealedValue {
        let plaintext = try VaultCodec.encoder().encode(payload)
        return try seal(
            plaintext,
            keyData: keyData,
            authenticatedData: payloadAAD(
                formatVersion: VaultEnvelope.currentFormatVersion,
                vaultID: vaultID
            )
        )
    }

    private static func seal(_ plaintext: Data, keyData: Data, authenticatedData: Data) throws -> SealedValue {
        let nonceData = try SecureRandom.bytes(count: nonceByteCount)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: keyData),
            nonce: nonce,
            authenticating: authenticatedData
        )
        return SealedValue(nonce: nonceData, ciphertext: sealed.ciphertext, tag: sealed.tag)
    }

    private static func open(_ value: SealedValue, keyData: Data, authenticatedData: Data) throws -> Data {
        guard value.nonce.count == nonceByteCount, value.tag.count == 16 else {
            throw VaultCryptoError.malformedEnvelope
        }
        let nonce = try AES.GCM.Nonce(data: value.nonce)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: value.ciphertext, tag: value.tag)
        return try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData), authenticating: authenticatedData)
    }

    private static func validate(_ envelope: VaultEnvelope) throws {
        guard envelope.formatVersion == VaultEnvelope.currentFormatVersion else {
            throw VaultCryptoError.unsupportedFormat
        }
        guard envelope.kdf.algorithm == KDFParameters.supportedAlgorithm else {
            throw VaultCryptoError.unsupportedKDF
        }
        do {
            try PasswordKDF.validate(envelope.kdf)
        } catch {
            throw VaultCryptoError.malformedEnvelope
        }
        guard envelope.wrappedDEK.ciphertext.count == vaultKeyByteCount,
              !envelope.payload.ciphertext.isEmpty else {
            throw VaultCryptoError.malformedEnvelope
        }
    }

    private static func wrapAAD(formatVersion: Int, vaultID: UUID, parameters: KDFParameters) -> Data {
        var data = Data("PasswordManager|wrap|\(formatVersion)|\(vaultID.uuidString.lowercased())|\(parameters.algorithm)|\(parameters.iterations)|".utf8)
        data.append(parameters.salt)
        return data
    }

    private static func payloadAAD(formatVersion: Int, vaultID: UUID) -> Data {
        Data("PasswordManager|payload|\(formatVersion)|\(vaultID.uuidString.lowercased())".utf8)
    }
}
