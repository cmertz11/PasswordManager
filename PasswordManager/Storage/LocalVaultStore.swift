import Foundation

enum LocalVaultStoreError: Error, Equatable {
    case applicationSupportUnavailable
    case noVault
}

struct LocalVaultStore: Sendable {
    let directoryURL: URL

    private var vaultURL: URL { directoryURL.appendingPathComponent("vault.pmvault") }
    private var backupURL: URL { directoryURL.appendingPathComponent("vault.previous.pmvault") }
    private var conflictsDirectoryURL: URL { directoryURL.appendingPathComponent("Conflicts", isDirectory: true) }
    private var pendingCloudConflictURL: URL { conflictsDirectoryURL.appendingPathComponent("pending-cloud-conflict.pmvault") }

    init(directoryURL: URL? = nil) throws {
        if let directoryURL {
            self.directoryURL = directoryURL
            return
        }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LocalVaultStoreError.applicationSupportUnavailable
        }
        self.directoryURL = applicationSupport.appendingPathComponent("PasswordManager", isDirectory: true)
    }

    func hasVault() -> Bool {
        FileManager.default.fileExists(atPath: vaultURL.path)
    }

    func loadData() throws -> Data {
        guard hasVault() else { throw LocalVaultStoreError.noVault }
        return try Data(contentsOf: vaultURL, options: .mappedIfSafe)
    }

    func loadEnvelope() throws -> VaultEnvelope {
        try VaultCodec.decodeEnvelope(from: loadData())
    }

    func loadPreviousData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        return try Data(contentsOf: backupURL, options: .mappedIfSafe)
    }

    func loadPendingCloudConflictData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: pendingCloudConflictURL.path) else { return nil }
        return try Data(contentsOf: pendingCloudConflictURL, options: .mappedIfSafe)
    }

    func savePendingCloudConflictData(_ data: Data) throws {
        try prepareConflictsDirectory()
        try writeProtectedData(data, to: pendingCloudConflictURL)
    }

    func clearPendingCloudConflictData() throws {
        guard FileManager.default.fileExists(atPath: pendingCloudConflictURL.path) else { return }
        try FileManager.default.removeItem(at: pendingCloudConflictURL)
    }

    func save(_ envelope: VaultEnvelope, previousKnownGood: VaultEnvelope? = nil) throws {
        try saveData(
            VaultCodec.encode(envelope),
            previousKnownGoodData: try previousKnownGood.map(VaultCodec.encode)
        )
    }

    func saveData(_ data: Data, previousKnownGoodData: Data? = nil) throws {
        let fileManager = FileManager.default
        try prepareDirectory()

        if fileManager.fileExists(atPath: vaultURL.path) {
            let backupData = try previousKnownGoodData ?? loadData()
            try writeProtectedData(backupData, to: backupURL)
        }

        try writeCurrentData(data)
    }

    /// Replaces an unreadable current envelope without rotating it over the last known-good backup.
    /// The unreadable encrypted bytes are retained in Conflicts for forensic/manual recovery.
    func recoverCurrentData(with data: Data) throws {
        try prepareDirectory()
        if hasVault() {
            try preserveConflictData(loadData())
        }
        try writeCurrentData(data)
    }

    private func prepareDirectory() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    private func writeCurrentData(_ data: Data) throws {
        try writeProtectedData(data, to: vaultURL)
    }

    private func writeProtectedData(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func prepareConflictsDirectory() throws {
        try prepareDirectory()
        try FileManager.default.createDirectory(
            at: conflictsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: conflictsDirectoryURL.path)
    }

    @discardableResult
    func preserveConflictData(_ data: Data) throws -> URL {
        try prepareConflictsDirectory()
        let filename = "cloud-conflict-\(UUID().uuidString.lowercased()).pmvault"
        let url = conflictsDirectoryURL.appendingPathComponent(filename)
        try writeProtectedData(data, to: url)
        return url
    }
}
