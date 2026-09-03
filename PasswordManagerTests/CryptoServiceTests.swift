import Foundation
import XCTest
@testable import PasswordManager

final class CryptoServiceTests: XCTestCase {
    private let testIterations = PasswordKDF.defaultIterations

    func testProductionKDFUsesHardenedWorkFactor() {
        XCTAssertGreaterThanOrEqual(PasswordKDF.defaultIterations, 600_000)
    }

    func testRoundTripPreservesPayload() throws {
        let credential = Credential(
            name: "Example",
            username: "person@example.com",
            password: "correct horse battery staple",
            website: "https://example.com",
            notes: "A private note"
        )
        let payload = VaultPayload(credentials: [credential])
        let created = try CryptoService.createVault(
            password: "a long test master password",
            payload: payload,
            iterations: testIterations
        )

        let encoded = try VaultCodec.encode(created.envelope)
        let decoded = try VaultCodec.decodeEnvelope(from: encoded)
        let unlocked = try CryptoService.unlock(decoded, password: "a long test master password")

        XCTAssertEqual(unlocked.payload, payload)
        XCTAssertEqual(unlocked.keyData.count, 32)
    }

    func testWrongPasswordIsRejected() throws {
        let created = try CryptoService.createVault(
            password: "right password for this vault",
            iterations: testIterations
        )

        XCTAssertThrowsError(try CryptoService.unlock(created.envelope, password: "wrong password")) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }
    }

    func testTamperedCiphertextIsRejected() throws {
        let created = try CryptoService.createVault(
            password: "a long test master password",
            payload: VaultPayload(credentials: [Credential(name: "Private")]),
            iterations: testIterations
        )
        var tampered = created.envelope
        var bytes = Array(tampered.payload.ciphertext)
        bytes[0] ^= 0x01
        tampered.payload.ciphertext = Data(bytes)

        XCTAssertThrowsError(try CryptoService.unlock(tampered, keyData: created.unlocked.keyData)) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }
    }

    func testHeaderSubstitutionIsRejected() throws {
        let created = try CryptoService.createVault(
            password: "a long test master password",
            iterations: testIterations
        )
        var tampered = created.envelope
        tampered.vaultID = UUID()

        XCTAssertThrowsError(try CryptoService.unlock(tampered, password: "a long test master password")) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }
    }

    func testTamperedPayloadTagIsRejected() throws {
        let created = try makeTestVault()
        var tampered = created.envelope
        tampered.payload.tag = togglingFirstByte(of: tampered.payload.tag)

        XCTAssertThrowsError(try CryptoService.unlock(tampered, keyData: created.unlocked.keyData)) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }
    }

    func testTamperedPayloadNonceIsRejected() throws {
        let created = try makeTestVault()
        var tampered = created.envelope
        tampered.payload.nonce = togglingFirstByte(of: tampered.payload.nonce)

        XCTAssertThrowsError(try CryptoService.unlock(tampered, keyData: created.unlocked.keyData)) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }
    }

    func testTamperedWrappedKeyIsRejected() throws {
        let created = try makeTestVault()
        var tampered = created.envelope
        tampered.wrappedDEK.ciphertext = togglingFirstByte(of: tampered.wrappedDEK.ciphertext)

        XCTAssertThrowsError(try CryptoService.unlock(tampered, password: "a long test master password")) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }
    }

    func testUnsupportedFormatIsRejected() throws {
        let created = try makeTestVault()
        var unsupported = created.envelope
        unsupported.formatVersion += 1

        XCTAssertThrowsError(try CryptoService.unlock(unsupported, keyData: created.unlocked.keyData)) { error in
            XCTAssertEqual(error as? VaultCryptoError, .unsupportedFormat)
        }
    }

    func testUnsupportedPayloadSchemaIsRejected() throws {
        let created = try CryptoService.createVault(
            password: "a long test master password",
            payload: VaultPayload(schemaVersion: VaultPayload.currentSchemaVersion + 1),
            iterations: testIterations
        )

        XCTAssertThrowsError(try CryptoService.unlock(created.envelope, keyData: created.unlocked.keyData)) { error in
            XCTAssertEqual(error as? VaultCryptoError, .unsupportedSchema)
        }
    }

    func testUnsafeKDFParametersAreRejectedBeforeDerivation() throws {
        let created = try makeTestVault()
        var unsafe = created.envelope
        unsafe.kdf.iterations = PasswordKDF.defaultIterations - 1

        XCTAssertThrowsError(try CryptoService.unlock(unsafe, password: "a long test master password")) { error in
            XCTAssertEqual(error as? VaultCryptoError, .malformedEnvelope)
        }

        unsafe = created.envelope
        unsafe.kdf.iterations = PasswordKDF.maximumSupportedIterations + 1
        XCTAssertThrowsError(try CryptoService.unlock(unsafe, password: "a long test master password")) { error in
            XCTAssertEqual(error as? VaultCryptoError, .malformedEnvelope)
        }
    }

    func testAuthenticatedKDFHeaderSubstitutionIsRejected() throws {
        let created = try makeTestVault()
        var tamperedSalt = created.envelope
        tamperedSalt.kdf.salt = togglingFirstByte(of: tamperedSalt.kdf.salt)
        XCTAssertThrowsError(try CryptoService.unlock(tamperedSalt, password: "a long test master password")) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }

        var tamperedIterations = created.envelope
        tamperedIterations.kdf.iterations += 1
        XCTAssertThrowsError(try CryptoService.unlock(tamperedIterations, password: "a long test master password")) { error in
            XCTAssertEqual(error as? VaultCryptoError, .authenticationFailed)
        }
    }

    func testRepeatedSavesUseDifferentCiphertext() throws {
        let created = try CryptoService.createVault(
            password: "a long test master password",
            iterations: testIterations
        )
        let first = try CryptoService.reseal(
            payload: created.unlocked.payload,
            preserving: created.envelope,
            keyData: created.unlocked.keyData
        )
        let second = try CryptoService.reseal(
            payload: created.unlocked.payload,
            preserving: created.envelope,
            keyData: created.unlocked.keyData
        )

        XCTAssertNotEqual(first.payload.nonce, second.payload.nonce)
        XCTAssertNotEqual(first.payload.ciphertext, second.payload.ciphertext)
    }

    private func makeTestVault() throws -> (envelope: VaultEnvelope, unlocked: UnlockedVault) {
        try CryptoService.createVault(
            password: "a long test master password",
            payload: VaultPayload(credentials: [Credential(name: "Private")]),
            iterations: testIterations
        )
    }

    private func togglingFirstByte(of data: Data) -> Data {
        var bytes = Array(data)
        bytes[0] ^= 0x01
        return Data(bytes)
    }
}
