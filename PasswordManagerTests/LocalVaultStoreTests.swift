import Foundation
import XCTest
@testable import PasswordManager

final class LocalVaultStoreTests: XCTestCase {
    func testSavesOnlyEncodedEnvelopeAndKeepsPreviousCopy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalVaultStore(directoryURL: directory)

        let first = try CryptoService.createVault(
            password: "a long test master password",
            payload: VaultPayload(credentials: [Credential(name: "First", password: "secret-one")]),
            iterations: PasswordKDF.defaultIterations
        ).envelope
        try store.save(first)

        let second = try CryptoService.createVault(
            password: "another long test password",
            payload: VaultPayload(credentials: [Credential(name: "Second", password: "secret-two")]),
            iterations: PasswordKDF.defaultIterations
        ).envelope
        try store.save(second)

        XCTAssertEqual(try store.loadEnvelope(), second)
        XCTAssertEqual(try store.loadPreviousData().map(VaultCodec.decodeEnvelope), first)
        let rawData = try store.loadData()
        XCTAssertNil(String(data: rawData, encoding: .utf8)?.range(of: "secret-two"))
        let previousRawData = try XCTUnwrap(store.loadPreviousData())
        XCTAssertNil(String(data: previousRawData, encoding: .utf8)?.range(of: "secret-one"))

        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        let vaultPermissions = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("vault.pmvault").path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
        XCTAssertEqual(vaultPermissions?.intValue, 0o600)
    }

    func testPreservesCloudConflictAsEncryptedData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalVaultStore(directoryURL: directory)
        let encryptedData = try VaultCodec.encode(
            CryptoService.createVault(
                password: "a long test master password",
                iterations: PasswordKDF.defaultIterations
            ).envelope
        )

        let conflictURL = try store.preserveConflictData(encryptedData)

        XCTAssertEqual(try Data(contentsOf: conflictURL), encryptedData)
        XCTAssertEqual(conflictURL.pathExtension, "pmvault")
    }

    func testRecoveryDoesNotRotateUnreadableCurrentDataOverPreviousCopy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalVaultStore(directoryURL: directory)
        let firstData = try VaultCodec.encode(
            CryptoService.createVault(
                password: "a long test master password",
                iterations: PasswordKDF.defaultIterations
            ).envelope
        )
        let secondData = try VaultCodec.encode(
            CryptoService.createVault(
                password: "another long test password",
                iterations: PasswordKDF.defaultIterations
            ).envelope
        )
        try store.saveData(firstData)
        try store.saveData(secondData)

        let unreadableData = Data("not a vault envelope".utf8)
        try unreadableData.write(to: directory.appendingPathComponent("vault.pmvault"), options: .atomic)
        try store.recoverCurrentData(with: firstData)

        XCTAssertEqual(try store.loadData(), firstData)
        XCTAssertEqual(try store.loadPreviousData(), firstData)
        let conflictFiles = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Conflicts", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(conflictFiles.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(conflictFiles.first)), unreadableData)
    }

    func testPendingCloudConflictRoundTripsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalVaultStore(directoryURL: directory)
        let encryptedData = try VaultCodec.encode(
            CryptoService.createVault(password: "a long test master password").envelope
        )

        try store.savePendingCloudConflictData(encryptedData)
        XCTAssertEqual(try store.loadPendingCloudConflictData(), encryptedData)
        try store.clearPendingCloudConflictData()
        XCTAssertNil(try store.loadPendingCloudConflictData())
    }

    func testSaveCanRotateAValidatedPreviousEnvelopeInsteadOfUnreadableDiskBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalVaultStore(directoryURL: directory)
        let previous = try CryptoService.createVault(password: "a long previous master password").envelope
        let current = try CryptoService.createVault(password: "a long current master password").envelope
        try store.save(previous)
        try Data("externally corrupted bytes".utf8).write(
            to: directory.appendingPathComponent("vault.pmvault"),
            options: .atomic
        )

        try store.save(current, previousKnownGood: previous)

        XCTAssertEqual(try store.loadEnvelope(), current)
        XCTAssertEqual(try store.loadPreviousData().map(VaultCodec.decodeEnvelope), previous)
    }
}
