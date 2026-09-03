import Foundation
import Observation

enum VaultMode: Equatable, Sendable {
    case loading
    case needsSetup
    case unavailable
    case locked
    case unlocked
}

enum SyncStatus: Equatable, Sendable {
    case localOnly
    case syncing
    case synced(Date)
    case offline
    case error

    var label: String {
        switch self {
        case .localOnly: "Saved locally"
        case .syncing: "Syncing…"
        case .synced: "Synced"
        case .offline: "Offline — saved locally"
        case .error: "Sync needs attention"
        }
    }
}

@MainActor
@Observable
final class VaultStore {
    private(set) var mode: VaultMode = .loading
    private(set) var payload = VaultPayload()
    private(set) var envelope: VaultEnvelope?
    private(set) var isBusy = false
    private(set) var syncStatus: SyncStatus = .localOnly
    var errorMessage: String?
    var selectedCredentialID: UUID?
    var searchText = ""
    var isPresentingEditor = false
    var isPresentingSettings = false
    var isPresentingConflictResolution = false

    private var keyData: Data?
    private var localStore: LocalVaultStore?
    private let keychain = KeychainService()
    private let cloudStore: (any CloudVaultStoring)?
    private let defaults: UserDefaults
    private var pendingCloudData: Data?
    private var unresolvedCloudData: Data?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var isSyncInProgress = false
    @ObservationIgnored private var needsAnotherSync = false
    @ObservationIgnored private var lockGeneration: UInt64 = 0

    private static let biometricPreferenceKey = "biometricQuickUnlockEnabled"
    private static let lastSuccessfulSyncKey = "lastSuccessfulCloudSync"

    init(
        defaults: UserDefaults = .standard,
        localStore suppliedLocalStore: LocalVaultStore? = nil,
        cloudStore suppliedCloudStore: (any CloudVaultStoring)? = nil,
        cloudEnabled: Bool = true
    ) {
        self.defaults = defaults
        #if DEBUG
        let uiTestRunID = ProcessInfo.processInfo.environment["PASSWORD_MANAGER_UI_TEST_RUN_ID"]
        #else
        let uiTestRunID: String? = nil
        #endif
        if let suppliedCloudStore {
            cloudStore = suppliedCloudStore
        } else if cloudEnabled,
                  AppConfiguration.cloudKitEnabled,
                  let cloudContainerIdentifier = AppConfiguration.cloudContainerIdentifier,
                  uiTestRunID == nil,
                  ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            cloudStore = CloudVaultStore(containerIdentifier: cloudContainerIdentifier)
        } else {
            cloudStore = nil
        }
        if let suppliedLocalStore {
            localStore = suppliedLocalStore
            return
        }
        if let uiTestRunID, let runUUID = UUID(uuidString: uiTestRunID) {
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PasswordManagerUITests", isDirectory: true)
                    .appendingPathComponent(runUUID.uuidString.lowercased(), isDirectory: true)
                localStore = try LocalVaultStore(directoryURL: directory)
            } catch {
                errorMessage = "PasswordManager could not create its isolated UI-test vault."
                mode = .unavailable
            }
            return
        }
        do {
            localStore = try LocalVaultStore()
        } catch {
            errorMessage = "PasswordManager could not access Application Support."
            mode = .needsSetup
        }
    }

    var credentials: [Credential] {
        payload.credentials.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.username.localizedStandardCompare($1.username) == .orderedAscending
        }
    }

    var filteredCredentials: [Credential] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return credentials }
        return credentials.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.username.localizedCaseInsensitiveContains(query) ||
            $0.website.localizedCaseInsensitiveContains(query) ||
            $0.sshHost.localizedCaseInsensitiveContains(query) ||
            $0.sshCommand.localizedCaseInsensitiveContains(query) ||
            $0.apiEndpoint.localizedCaseInsensitiveContains(query)
        }
    }

    var isCloudSyncEnabled: Bool {
        cloudStore != nil
    }

    var selectedCredential: Credential? {
        guard let selectedCredentialID else { return nil }
        return payload.credentials.first { $0.id == selectedCredentialID }
    }

    var biometricAvailability: BiometricAvailability {
        BiometricService.availability()
    }

    var biometricQuickUnlockEnabled: Bool {
        defaults.bool(forKey: Self.biometricPreferenceKey)
    }

    var hasUnresolvedCloudConflict: Bool {
        unresolvedCloudData != nil
    }

    var lastSuccessfulSyncDate: Date? {
        if case .synced(let date) = syncStatus { return date }
        return defaults.object(forKey: Self.lastSuccessfulSyncKey) as? Date
    }

    func bootstrap() async {
        guard mode == .loading, let localStore else { return }

        var localEnvelope: VaultEnvelope?
        var localVaultIsUnreadable = false
        do {
            if localStore.hasVault() {
                localEnvelope = try localStore.loadEnvelope()
            }
        } catch {
            localVaultIsUnreadable = true
            do {
                guard let previousData = try localStore.loadPreviousData() else {
                    throw LocalVaultStoreError.noVault
                }
                let previousEnvelope = try VaultCodec.decodeEnvelope(from: previousData)
                try localStore.recoverCurrentData(with: previousData)
                localEnvelope = previousEnvelope
                localVaultIsUnreadable = false
                errorMessage = "The current encrypted vault was unreadable, so the previous encrypted copy was restored."
            } catch {
                errorMessage = "The encrypted vault could not be read. Existing encrypted files were left untouched."
            }
        }

        do {
            unresolvedCloudData = try localStore.loadPendingCloudConflictData()
        } catch {
            errorMessage = "A preserved encrypted sync conflict could not be read. Existing files were left untouched."
        }

        do {
            if let cloudStore, let cloudData = try await cloudStore.fetch() {
                let cloudEnvelope = try VaultCodec.decodeEnvelope(from: cloudData)
                if localEnvelope == nil {
                    if localVaultIsUnreadable {
                        try localStore.recoverCurrentData(with: cloudData)
                    } else {
                        try localStore.saveData(cloudData)
                    }
                    localEnvelope = cloudEnvelope
                    localVaultIsUnreadable = false
                    unresolvedCloudData = nil
                    try localStore.clearPendingCloudConflictData()
                } else if try VaultCodec.encode(localEnvelope!) != cloudData {
                    if unresolvedCloudData != nil {
                        try localStore.savePendingCloudConflictData(cloudData)
                        unresolvedCloudData = cloudData
                    } else {
                        pendingCloudData = cloudData
                    }
                } else if unresolvedCloudData != nil {
                    unresolvedCloudData = nil
                    try localStore.clearPendingCloudConflictData()
                }
                if unresolvedCloudData != nil {
                    syncStatus = .error
                } else if pendingCloudData != nil {
                    syncStatus = .localOnly
                } else {
                    markSyncSuccessful()
                }
            }
        } catch {
            syncStatus = .offline
        }

        envelope = localEnvelope
        if localEnvelope != nil {
            mode = .locked
        } else {
            mode = localVaultIsUnreadable ? .unavailable : .needsSetup
        }
    }

    func retryBootstrap() async {
        guard mode == .unavailable else { return }
        errorMessage = nil
        mode = .loading
        await bootstrap()
    }

    func createVault(masterPassword: String, enableBiometrics: Bool) async -> Bool {
        guard mode == .needsSetup else {
            errorMessage = "A new vault cannot be created while encrypted vault data already exists."
            return false
        }
        guard masterPassword.count >= 12, let localStore else {
            errorMessage = "Use a master password with at least 12 characters."
            return false
        }

        isBusy = true
        errorMessage = nil
        let expectedLockGeneration = lockGeneration
        defer { isBusy = false }

        do {
            var created = try await Task.detached(priority: .userInitiated) {
                try CryptoService.createVault(password: masterPassword)
            }.value
            guard lockGeneration == expectedLockGeneration, mode == .needsSetup else {
                clearUnlockedVault(&created.unlocked)
                return false
            }
            try localStore.save(created.envelope)
            envelope = created.envelope
            payload = created.unlocked.payload
            keyData = created.unlocked.keyData
            mode = .unlocked
            if enableBiometrics {
                do {
                    try setBiometricQuickUnlock(true)
                } catch {
                    errorMessage = "The vault was created, but biometric quick unlock could not be enabled."
                }
            }
            Task { await syncNow() }
            return true
        } catch {
            errorMessage = safeMessage(operation: "create the encrypted vault")
            return false
        }
    }

    func unlock(masterPassword: String) async -> Bool {
        guard let envelope else {
            errorMessage = "No encrypted vault is available."
            return false
        }
        guard !masterPassword.isEmpty else {
            errorMessage = "Enter the master password."
            return false
        }

        isBusy = true
        errorMessage = nil
        let expectedLockGeneration = lockGeneration
        defer { isBusy = false }

        do {
            var unlocked = try await Task.detached(priority: .userInitiated) {
                try CryptoService.unlock(envelope, password: masterPassword)
            }.value
            guard lockGeneration == expectedLockGeneration, mode == .locked else {
                clearUnlockedVault(&unlocked)
                return false
            }
            finishUnlock(unlocked)
            Task { await syncNow() }
            return true
        } catch let cryptoError as VaultCryptoError {
            if await recoverPreviousEnvelope(
                masterPassword: masterPassword,
                expectedLockGeneration: expectedLockGeneration
            ) {
                return true
            }
            if cryptoError == .authenticationFailed {
                errorMessage = "The master password is incorrect, or the encrypted vault has been modified."
            } else {
                errorMessage = "The encrypted vault format is unsupported or malformed. Existing files were left untouched."
            }
            return false
        } catch {
            errorMessage = safeMessage(operation: "unlock the vault")
            return false
        }
    }

    func unlockWithBiometrics() async -> Bool {
        guard let envelope else {
            errorMessage = "No encrypted vault is available."
            return false
        }

        isBusy = true
        errorMessage = nil
        let expectedLockGeneration = lockGeneration
        defer { isBusy = false }

        do {
            let prompt = "Unlock your encrypted password vault"
            var key = try await Task.detached(priority: .userInitiated) { [keychain] in
                try keychain.retrieveVaultKey(vaultID: envelope.vaultID, prompt: prompt)
            }.value
            defer { key.resetBytes(in: 0..<key.count) }
            guard lockGeneration == expectedLockGeneration, mode == .locked else {
                return false
            }
            let unlocked: UnlockedVault
            do {
                unlocked = try CryptoService.unlock(envelope, keyData: key)
            } catch {
                guard recoverPreviousEnvelope(
                    keyData: key,
                    expectedLockGeneration: expectedLockGeneration
                ) else { throw error }
                return true
            }
            finishUnlock(unlocked)
            Task { await syncNow() }
            return true
        } catch KeychainServiceError.cancelled {
            return false
        } catch {
            errorMessage = "Quick unlock was unavailable. Enter the master password instead."
            return false
        }
    }

    func lock() {
        lockGeneration &+= 1
        syncTask?.cancel()
        syncTask = nil
        clearInMemoryKey()
        payload = VaultPayload()
        selectedCredentialID = nil
        searchText = ""
        errorMessage = nil
        if envelope != nil {
            mode = .locked
        }
    }

    func saveCredential(_ credential: Credential) -> Bool {
        guard mode == .unlocked else { return false }
        guard !hasUnresolvedCloudConflict else {
            errorMessage = "Resolve the encrypted iCloud conflict before making changes."
            isPresentingConflictResolution = true
            return false
        }
        let previousPayload = payload
        let previousSelection = selectedCredentialID
        var updated = credential
        updated.markUpdated()
        payload.upsert(updated)
        selectedCredentialID = updated.id
        let saved = persistCurrentPayload()
        if saved {
            scheduleSync()
        } else {
            payload = previousPayload
            selectedCredentialID = previousSelection
        }
        return saved
    }

    func deleteCredential(id: UUID) -> Bool {
        guard mode == .unlocked else { return false }
        guard !hasUnresolvedCloudConflict else {
            errorMessage = "Resolve the encrypted iCloud conflict before making changes."
            isPresentingConflictResolution = true
            return false
        }
        let previousPayload = payload
        let previousSelection = selectedCredentialID
        payload.delete(credentialID: id)
        if selectedCredentialID == id { selectedCredentialID = nil }
        let saved = persistCurrentPayload()
        if saved {
            scheduleSync()
        } else {
            payload = previousPayload
            selectedCredentialID = previousSelection
        }
        return saved
    }

    func setBiometricQuickUnlock(_ enabled: Bool) throws {
        guard let envelope else { return }
        if enabled {
            guard biometricAvailability.isAvailable, let keyData else {
                throw KeychainServiceError.biometryUnavailable
            }
            try keychain.storeVaultKey(keyData, vaultID: envelope.vaultID)
            defaults.set(true, forKey: Self.biometricPreferenceKey)
        } else {
            try keychain.deleteVaultKey(vaultID: envelope.vaultID)
            defaults.set(false, forKey: Self.biometricPreferenceKey)
        }
    }

    func encryptedBackupData() throws -> Data {
        guard let envelope else { throw LocalVaultStoreError.noVault }
        return try VaultCodec.encode(envelope)
    }

    func syncNow() async {
        guard mode == .unlocked, envelope != nil, keyData != nil else { return }
        if isSyncInProgress {
            needsAnotherSync = true
            return
        }
        guard !hasUnresolvedCloudConflict else {
            syncStatus = .error
            isPresentingConflictResolution = true
            return
        }
        guard let cloudStore else {
            syncStatus = .localOnly
            return
        }
        isSyncInProgress = true
        defer {
            isSyncInProgress = false
            if needsAnotherSync {
                needsAnotherSync = false
                Task { @MainActor [weak self] in
                    await self?.syncNow()
                }
            }
        }
        syncTask?.cancel()
        syncTask = nil
        syncStatus = .syncing

        let remoteData: Data?
        if let pendingCloudData {
            remoteData = pendingCloudData
            self.pendingCloudData = nil
        } else {
            do {
                remoteData = try await cloudStore.fetch()
            } catch {
                if let cloudError = error as? CloudVaultStoreError, cloudError.isConnectivityIssue {
                    syncStatus = .offline
                } else {
                    syncStatus = .error
                    errorMessage = "The encrypted iCloud vault could not be read safely."
                }
                return
            }
        }

        guard mode == .unlocked else { return }
        do {
            if let remoteData {
                try await mergeAndUploadIfNeeded(remoteData: remoteData, mayRetry: true)
            } else {
                try await uploadCurrentEnvelope(mayRetry: true)
            }
            markSyncSuccessful()
            errorMessage = nil
        } catch {
            if let cloudError = error as? CloudVaultStoreError, cloudError.isConnectivityIssue {
                syncStatus = .offline
            } else {
                syncStatus = .error
                errorMessage = "The iCloud copy could not be safely merged. Both encrypted copies were preserved."
            }
        }
    }

    func resolveCloudConflictKeepingLocal() async -> Bool {
        guard hasUnresolvedCloudConflict,
              mode == .unlocked,
              let envelope,
              let cloudStore else { return false }

        isBusy = true
        syncStatus = .syncing
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await cloudStore.save(VaultCodec.encode(envelope))
            try localStore?.clearPendingCloudConflictData()
            unresolvedCloudData = nil
            isPresentingConflictResolution = false
            markSyncSuccessful()
            return true
        } catch CloudVaultStoreError.serverRecordChanged(let newestServerData) {
            try? preserveCloudConflict(newestServerData)
            syncStatus = .error
            errorMessage = "The iCloud copy changed again. Review the conflict before retrying."
            return false
        } catch {
            syncStatus = (error as? CloudVaultStoreError)?.isConnectivityIssue == true ? .offline : .error
            errorMessage = "The device copy could not be uploaded. No encrypted copy was discarded."
            return false
        }
    }

    func resolveCloudConflictUsingCloud(masterPassword: String) async -> Bool {
        guard let remoteData = unresolvedCloudData,
              let currentEnvelope = envelope,
              let localStore else { return false }
        guard !masterPassword.isEmpty else {
            errorMessage = "Enter the master password for the iCloud copy."
            return false
        }

        isBusy = true
        errorMessage = nil
        let expectedLockGeneration = lockGeneration
        defer { isBusy = false }

        do {
            let remoteEnvelope = try VaultCodec.decodeEnvelope(from: remoteData)
            var unlocked = try await Task.detached(priority: .userInitiated) {
                try CryptoService.unlock(remoteEnvelope, password: masterPassword)
            }.value
            guard lockGeneration == expectedLockGeneration, mode == .unlocked else {
                clearUnlockedVault(&unlocked)
                return false
            }

            try localStore.preserveConflictData(VaultCodec.encode(currentEnvelope))
            try localStore.saveData(
                remoteData,
                previousKnownGoodData: VaultCodec.encode(currentEnvelope)
            )
            try localStore.clearPendingCloudConflictData()
            try? keychain.deleteVaultKey(vaultID: currentEnvelope.vaultID)
            defaults.set(false, forKey: Self.biometricPreferenceKey)

            envelope = remoteEnvelope
            payload = unlocked.payload
            clearInMemoryKey()
            keyData = unlocked.keyData
            unresolvedCloudData = nil
            pendingCloudData = nil
            isPresentingConflictResolution = false
            selectedCredentialID = credentials.first?.id
            syncStatus = .localOnly
            Task { await syncNow() }
            return true
        } catch VaultCryptoError.authenticationFailed {
            errorMessage = "That password could not unlock the encrypted iCloud copy. Nothing was replaced."
            return false
        } catch {
            errorMessage = "The encrypted iCloud copy could not be verified. Nothing was replaced."
            return false
        }
    }

    private func finishUnlock(_ unlocked: UnlockedVault) {
        payload = unlocked.payload
        clearInMemoryKey()
        keyData = unlocked.keyData
        mode = .unlocked
        errorMessage = nil
        if selectedCredentialID == nil {
            selectedCredentialID = credentials.first?.id
        }
    }

    private func recoverPreviousEnvelope(
        masterPassword: String,
        expectedLockGeneration: UInt64
    ) async -> Bool {
        guard let localStore,
              let previousData = try? localStore.loadPreviousData(),
              let previousEnvelope = try? VaultCodec.decodeEnvelope(from: previousData) else {
            return false
        }
        do {
            var unlocked = try await Task.detached(priority: .userInitiated) {
                try CryptoService.unlock(previousEnvelope, password: masterPassword)
            }.value
            guard lockGeneration == expectedLockGeneration, mode == .locked else {
                clearUnlockedVault(&unlocked)
                return false
            }
            try localStore.recoverCurrentData(with: previousData)
            envelope = previousEnvelope
            finishUnlock(unlocked)
            errorMessage = "The current vault failed verification. The previous encrypted copy was restored, and the damaged copy was preserved."
            Task { await syncNow() }
            return true
        } catch {
            return false
        }
    }

    private func recoverPreviousEnvelope(
        keyData: Data,
        expectedLockGeneration: UInt64
    ) -> Bool {
        guard lockGeneration == expectedLockGeneration,
              mode == .locked,
              let localStore,
              let previousData = try? localStore.loadPreviousData(),
              let previousEnvelope = try? VaultCodec.decodeEnvelope(from: previousData),
              var unlocked = try? CryptoService.unlock(previousEnvelope, keyData: keyData) else {
            return false
        }
        do {
            try localStore.recoverCurrentData(with: previousData)
            envelope = previousEnvelope
            finishUnlock(unlocked)
            errorMessage = "The current vault failed verification. The previous encrypted copy was restored, and the damaged copy was preserved."
            Task { await syncNow() }
            return true
        } catch {
            clearUnlockedVault(&unlocked)
            return false
        }
    }

    private func persistCurrentPayload() -> Bool {
        guard let envelope, let keyData, let localStore else { return false }
        do {
            let updatedEnvelope = try CryptoService.reseal(
                payload: payload,
                preserving: envelope,
                keyData: keyData
            )
            try localStore.save(updatedEnvelope, previousKnownGood: envelope)
            self.envelope = updatedEnvelope
            syncStatus = .localOnly
            errorMessage = nil
            return true
        } catch {
            errorMessage = safeMessage(operation: "save the encrypted vault")
            return false
        }
    }

    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func uploadCurrentEnvelope(mayRetry: Bool) async throws {
        guard let envelope, let cloudStore else { return }
        let data = try VaultCodec.encode(envelope)
        do {
            try await cloudStore.save(data)
        } catch CloudVaultStoreError.serverRecordChanged(let serverData) where mayRetry {
            try await mergeAndUploadIfNeeded(remoteData: serverData, mayRetry: false)
        } catch CloudVaultStoreError.serverRecordChanged(let serverData) {
            try preserveCloudConflict(serverData)
            throw CloudVaultStoreError.serverRecordChanged(serverData: serverData)
        } catch {
            throw error
        }
    }

    private func mergeAndUploadIfNeeded(remoteData: Data, mayRetry: Bool) async throws {
        guard mode == .unlocked,
              let localEnvelope = envelope,
              let keyData,
              let localStore,
              let cloudStore else { return }

        let remoteEnvelope: VaultEnvelope
        let remotePayload: VaultPayload
        do {
            remoteEnvelope = try VaultCodec.decodeEnvelope(from: remoteData)
            guard remoteEnvelope.vaultID == localEnvelope.vaultID else {
                throw CloudVaultStoreError.malformedResponse
            }
            remotePayload = try CryptoService.unlock(remoteEnvelope, keyData: keyData).payload
        } catch {
            try preserveCloudConflict(remoteData)
            throw error
        }

        let mergedPayload = payload.merged(with: remotePayload)
        if mergedPayload == remotePayload {
            try localStore.saveData(
                remoteData,
                previousKnownGoodData: VaultCodec.encode(localEnvelope)
            )
            envelope = remoteEnvelope
            payload = remotePayload
            return
        }

        let mergedEnvelope = try CryptoService.reseal(
            payload: mergedPayload,
            preserving: remoteEnvelope,
            keyData: keyData
        )
        let mergedData = try VaultCodec.encode(mergedEnvelope)
        try localStore.saveData(
            mergedData,
            previousKnownGoodData: VaultCodec.encode(localEnvelope)
        )
        envelope = mergedEnvelope
        payload = mergedPayload

        do {
            try await cloudStore.save(mergedData)
        } catch CloudVaultStoreError.serverRecordChanged(let newerServerData) where mayRetry {
            try await mergeAndUploadIfNeeded(remoteData: newerServerData, mayRetry: false)
        } catch CloudVaultStoreError.serverRecordChanged(let newerServerData) {
            try preserveCloudConflict(newerServerData)
            throw CloudVaultStoreError.serverRecordChanged(serverData: newerServerData)
        }
    }

    private func preserveCloudConflict(_ data: Data) throws {
        _ = try localStore?.preserveConflictData(data)
        try localStore?.savePendingCloudConflictData(data)
        unresolvedCloudData = data
        isPresentingConflictResolution = true
    }

    private func markSyncSuccessful(at date: Date = Date()) {
        syncStatus = .synced(date)
        defaults.set(date, forKey: Self.lastSuccessfulSyncKey)
    }

    private func safeMessage(operation: String) -> String {
        "PasswordManager could not \(operation). Your credential values were not logged."
    }

    private func clearInMemoryKey() {
        guard let count = keyData?.count else { return }
        keyData?.resetBytes(in: 0..<count)
        keyData = nil
    }

    private func clearUnlockedVault(_ unlocked: inout UnlockedVault) {
        unlocked.keyData.resetBytes(in: 0..<unlocked.keyData.count)
        unlocked.payload = VaultPayload()
    }
}
