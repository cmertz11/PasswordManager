import Foundation
import XCTest
@testable import PasswordManager

@MainActor
final class VaultStoreTests: XCTestCase {
    func testCreateSaveLockAndUnlockWorkflow() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "PasswordManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let localStore = try LocalVaultStore(directoryURL: directory)
        let firstStore = VaultStore(
            defaults: defaults,
            localStore: localStore,
            cloudEnabled: false
        )

        await firstStore.bootstrap()
        XCTAssertEqual(firstStore.mode, .needsSetup)
        let created = await firstStore.createVault(
            masterPassword: "a strong local master password",
            enableBiometrics: false
        )
        XCTAssertTrue(created)

        let credential = Credential(
            name: "Example Login",
            username: "person@example.com",
            password: "generated-value"
        )
        XCTAssertTrue(firstStore.saveCredential(credential))
        firstStore.lock()
        XCTAssertEqual(firstStore.mode, .locked)
        XCTAssertTrue(firstStore.credentials.isEmpty)

        let relaunchedStore = VaultStore(
            defaults: defaults,
            localStore: localStore,
            cloudEnabled: false
        )
        await relaunchedStore.bootstrap()
        XCTAssertEqual(relaunchedStore.mode, .locked)
        let wrongPasswordUnlocked = await relaunchedStore.unlock(masterPassword: "the wrong password")
        XCTAssertFalse(wrongPasswordUnlocked)
        let correctPasswordUnlocked = await relaunchedStore.unlock(
            masterPassword: "a strong local master password"
        )
        XCTAssertTrue(correctPasswordUnlocked)
        XCTAssertEqual(relaunchedStore.mode, .unlocked)
        XCTAssertEqual(relaunchedStore.credentials.count, 1)
        XCTAssertEqual(relaunchedStore.credentials.first?.name, "Example Login")
        XCTAssertEqual(relaunchedStore.credentials.first?.password, "generated-value")
    }

    func testBootstrapRestoresPreviousEnvelopeWhenCurrentFileIsUnreadable() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let password = "a strong recovery master password"
        let first = try CryptoService.createVault(
            password: password,
            payload: VaultPayload(credentials: [Credential(name: "Known Good")])
        ).envelope
        let second = try CryptoService.createVault(
            password: "another strong master password"
        ).envelope
        try fixture.localStore.save(first)
        try fixture.localStore.save(second)
        try Data("unreadable current envelope".utf8).write(
            to: fixture.directory.appendingPathComponent("vault.pmvault"),
            options: .atomic
        )

        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudEnabled: false
        )
        await store.bootstrap()

        XCTAssertEqual(store.mode, .locked)
        XCTAssertTrue(store.errorMessage?.contains("previous encrypted copy was restored") == true)
        let didUnlock = await store.unlock(masterPassword: password)
        XCTAssertTrue(didUnlock)
        XCTAssertEqual(store.credentials.map(\.name), ["Known Good"])
    }

    func testBootstrapNeverOffersSetupOverAnUnreadableVaultWithoutRecoveryCopy() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(
            at: fixture.directory,
            withIntermediateDirectories: true
        )
        try Data("unreadable current envelope".utf8).write(
            to: fixture.directory.appendingPathComponent("vault.pmvault"),
            options: .atomic
        )

        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudEnabled: false
        )
        await store.bootstrap()

        XCTAssertEqual(store.mode, .unavailable)
        let didCreate = await store.createVault(
            masterPassword: "a replacement master password",
            enableBiometrics: false
        )
        XCTAssertFalse(didCreate)
    }

    func testUnmergeableCloudVaultPausesEditingAndCanBeVerifiedBeforeReplacement() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let localPassword = "a strong local master password"
        let cloudPassword = "a different cloud master password"
        let localEnvelope = try CryptoService.createVault(
            password: localPassword,
            payload: VaultPayload(credentials: [Credential(name: "Local Login")])
        ).envelope
        let cloudEnvelope = try CryptoService.createVault(
            password: cloudPassword,
            payload: VaultPayload(credentials: [Credential(name: "Cloud Login")])
        ).envelope
        try fixture.localStore.save(localEnvelope)
        let cloudData = try VaultCodec.encode(cloudEnvelope)
        let cloud = TestCloudVaultStore(data: cloudData)
        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudStore: cloud
        )

        await store.bootstrap()
        let didUnlockLocal = await store.unlock(masterPassword: localPassword)
        XCTAssertTrue(didUnlockLocal)
        await waitUntil { store.hasUnresolvedCloudConflict }

        XCTAssertTrue(store.hasUnresolvedCloudConflict)
        XCTAssertEqual(try fixture.localStore.loadPendingCloudConflictData(), cloudData)
        store.lock()

        let relaunchedStore = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudStore: cloud
        )
        await relaunchedStore.bootstrap()
        XCTAssertEqual(relaunchedStore.mode, .locked)
        XCTAssertTrue(relaunchedStore.hasUnresolvedCloudConflict)
        let didUnlockRelaunched = await relaunchedStore.unlock(masterPassword: localPassword)
        XCTAssertTrue(didUnlockRelaunched)
        XCTAssertFalse(relaunchedStore.saveCredential(Credential(name: "Must Not Save")))
        let didAcceptWrongPassword = await relaunchedStore.resolveCloudConflictUsingCloud(masterPassword: "wrong password")
        XCTAssertFalse(didAcceptWrongPassword)
        XCTAssertTrue(relaunchedStore.hasUnresolvedCloudConflict)
        let didUseCloud = await relaunchedStore.resolveCloudConflictUsingCloud(masterPassword: cloudPassword)
        XCTAssertTrue(didUseCloud)
        XCTAssertFalse(relaunchedStore.hasUnresolvedCloudConflict)
        XCTAssertEqual(relaunchedStore.credentials.map(\.name), ["Cloud Login"])
        XCTAssertNil(try fixture.localStore.loadPendingCloudConflictData())
    }

    func testUnmergeableCloudVaultCanBeExplicitlyReplacedWithLocalCopy() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let localPassword = "a strong local master password"
        let localEnvelope = try CryptoService.createVault(
            password: localPassword,
            payload: VaultPayload(credentials: [Credential(name: "Local Login")])
        ).envelope
        let cloudEnvelope = try CryptoService.createVault(
            password: "a different cloud master password",
            payload: VaultPayload(credentials: [Credential(name: "Cloud Login")])
        ).envelope
        try fixture.localStore.save(localEnvelope)
        let cloud = TestCloudVaultStore(data: try VaultCodec.encode(cloudEnvelope))
        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudStore: cloud
        )

        await store.bootstrap()
        let didUnlock = await store.unlock(masterPassword: localPassword)
        XCTAssertTrue(didUnlock)
        await waitUntil { store.hasUnresolvedCloudConflict }

        let didKeepLocal = await store.resolveCloudConflictKeepingLocal()
        XCTAssertTrue(didKeepLocal)
        XCTAssertFalse(store.hasUnresolvedCloudConflict)
        let fetchedUploadedData = try await cloud.fetch()
        let uploadedData = try XCTUnwrap(fetchedUploadedData)
        let uploadedEnvelope = try VaultCodec.decodeEnvelope(from: uploadedData)
        let uploaded = try CryptoService.unlock(uploadedEnvelope, password: localPassword)
        XCTAssertEqual(uploaded.payload.credentials.map(\.name), ["Local Login"])
        XCTAssertNil(try fixture.localStore.loadPendingCloudConflictData())
    }

    func testCompatibleCloudAndLocalChangesMergeAndUpload() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let password = "a strong shared master password"
        let base = try CryptoService.createVault(password: password)
        let localEnvelope = try CryptoService.reseal(
            payload: VaultPayload(credentials: [Credential(name: "Local Login")]),
            preserving: base.envelope,
            keyData: base.unlocked.keyData
        )
        let remoteEnvelope = try CryptoService.reseal(
            payload: VaultPayload(credentials: [Credential(name: "Cloud Login")]),
            preserving: base.envelope,
            keyData: base.unlocked.keyData
        )
        try fixture.localStore.save(localEnvelope)
        let cloud = TestCloudVaultStore(data: try VaultCodec.encode(remoteEnvelope))
        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudStore: cloud
        )

        await store.bootstrap()
        let didUnlock = await store.unlock(masterPassword: password)
        XCTAssertTrue(didUnlock)
        await waitUntil { store.credentials.count == 2 }

        XCTAssertEqual(Set(store.credentials.map(\.name)), Set(["Local Login", "Cloud Login"]))
        XCTAssertFalse(store.hasUnresolvedCloudConflict)
        let fetchedUploadedData = try await cloud.fetch()
        let uploadedData = try XCTUnwrap(fetchedUploadedData)
        let uploadedEnvelope = try VaultCodec.decodeEnvelope(from: uploadedData)
        let uploaded = try CryptoService.unlock(uploadedEnvelope, keyData: base.unlocked.keyData)
        XCTAssertEqual(Set(uploaded.payload.credentials.map(\.name)), Set(["Local Login", "Cloud Login"]))
    }

    func testOfflineCloudKeepsTheUnlockedVaultUsableAndChangesLocal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let password = "a strong offline master password"
        let envelope = try CryptoService.createVault(
            password: password,
            payload: VaultPayload(credentials: [Credential(name: "Existing Login")])
        ).envelope
        try fixture.localStore.save(envelope)
        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudStore: OfflineCloudVaultStore()
        )

        await store.bootstrap()
        XCTAssertEqual(store.mode, .locked)
        XCTAssertEqual(store.syncStatus, .offline)
        let didUnlock = await store.unlock(masterPassword: password)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(store.saveCredential(Credential(name: "Offline Change")))
        await waitUntil { store.syncStatus == .offline }

        XCTAssertEqual(Set(store.credentials.map(\.name)), Set(["Existing Login", "Offline Change"]))
        XCTAssertEqual(store.syncStatus, .offline)
        let persisted = try CryptoService.unlock(fixture.localStore.loadEnvelope(), password: password)
        XCTAssertEqual(Set(persisted.payload.credentials.map(\.name)), Set(["Existing Login", "Offline Change"]))
    }

    func testEncryptedBackupContainsAnUnlockableEnvelopeAndNoPlaintextCredential() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let password = "a strong backup master password"
        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudEnabled: false
        )
        await store.bootstrap()
        let didCreate = await store.createVault(masterPassword: password, enableBiometrics: false)
        XCTAssertTrue(didCreate)
        XCTAssertTrue(store.saveCredential(Credential(
            name: "Backup Login",
            password: "known-backup-plaintext-value"
        )))
        XCTAssertTrue(store.saveCredential(Credential(
            name: "Backup API Key",
            kind: .apiKey,
            apiKey: "known-api-key-plaintext-value"
        )))

        let backup = try store.encryptedBackupData()
        XCTAssertFalse(String(decoding: backup, as: UTF8.self).contains("known-backup-plaintext-value"))
        XCTAssertFalse(String(decoding: backup, as: UTF8.self).contains("known-api-key-plaintext-value"))
        let restoredEnvelope = try VaultCodec.decodeEnvelope(from: backup)
        let restored = try CryptoService.unlock(restoredEnvelope, password: password)
        let restoredLogin = restored.payload.credentials.first { $0.name == "Backup Login" }
        let restoredAPIKey = restored.payload.credentials.first { $0.kind == .apiKey }
        XCTAssertEqual(restoredLogin?.password, "known-backup-plaintext-value")
        XCTAssertEqual(restoredAPIKey?.apiKey, "known-api-key-plaintext-value")
    }

    func testLockInvalidatesAnUnlockAlreadyDerivingTheMasterKey() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let password = "a strong race test master password"
        try fixture.localStore.save(CryptoService.createVault(
            password: password,
            payload: VaultPayload(credentials: [Credential(name: "Must Stay Locked")])
        ).envelope)
        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudEnabled: false
        )
        await store.bootstrap()

        let unlockTask = Task { await store.unlock(masterPassword: password) }
        while !store.isBusy { await Task.yield() }
        store.lock()
        let didUnlock = await unlockTask.value

        XCTAssertFalse(didUnlock)
        XCTAssertEqual(store.mode, .locked)
        XCTAssertTrue(store.credentials.isEmpty)
    }

    func testAuthenticatedUnlockRestoresPreviousCopyWhenCurrentCiphertextWasTampered() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let password = "a strong tamper recovery password"
        let created = try CryptoService.createVault(
            password: password,
            payload: VaultPayload(credentials: [Credential(name: "Known Good")])
        )
        let newer = try CryptoService.reseal(
            payload: VaultPayload(credentials: [Credential(name: "Newer Copy")]),
            preserving: created.envelope,
            keyData: created.unlocked.keyData
        )
        try fixture.localStore.save(created.envelope)
        try fixture.localStore.save(newer)
        var tampered = newer
        var ciphertext = Array(tampered.payload.ciphertext)
        ciphertext[0] ^= 0x01
        tampered.payload.ciphertext = Data(ciphertext)
        try VaultCodec.encode(tampered).write(
            to: fixture.directory.appendingPathComponent("vault.pmvault"),
            options: .atomic
        )

        let store = VaultStore(
            defaults: fixture.defaults,
            localStore: fixture.localStore,
            cloudEnabled: false
        )
        await store.bootstrap()
        let didUnlock = await store.unlock(masterPassword: password)

        XCTAssertTrue(didUnlock)
        XCTAssertEqual(store.credentials.map(\.name), ["Known Good"])
        XCTAssertTrue(store.errorMessage?.contains("previous encrypted copy was restored") == true)
        let restored = try CryptoService.unlock(fixture.localStore.loadEnvelope(), password: password)
        XCTAssertEqual(restored.payload.credentials.map(\.name), ["Known Good"])
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func makeFixture() throws -> VaultStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "PasswordManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return VaultStoreFixture(
            directory: directory,
            suiteName: suiteName,
            defaults: defaults,
            localStore: try LocalVaultStore(directoryURL: directory)
        )
    }
}

private struct VaultStoreFixture {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults
    let localStore: LocalVaultStore

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private actor TestCloudVaultStore: CloudVaultStoring {
    private var data: Data?

    init(data: Data?) {
        self.data = data
    }

    func fetch() async throws -> Data? {
        data
    }

    func save(_ data: Data) async throws {
        self.data = data
    }
}

private actor OfflineCloudVaultStore: CloudVaultStoring {
    func fetch() async throws -> Data? {
        throw CloudVaultStoreError.temporarilyUnavailable
    }

    func save(_ data: Data) async throws {
        throw CloudVaultStoreError.temporarilyUnavailable
    }
}
