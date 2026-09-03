@preconcurrency import CloudKit
import Foundation

enum CloudVaultStoreError: Error, Equatable, Sendable {
    case accountUnavailable
    case temporarilyUnavailable
    case missingBlob
    case malformedResponse
    case serverRecordChanged(serverData: Data)

    var isConnectivityIssue: Bool {
        self == .accountUnavailable || self == .temporarilyUnavailable
    }
}

protocol CloudVaultStoring: Sendable {
    func fetch() async throws -> Data?
    func save(_ data: Data) async throws
}

actor CloudVaultStore: CloudVaultStoring {
    private let container: CKContainer
    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: "primary-vault")
    private let recordType = "EncryptedVault"
    private let blobKey = "blob"
    private var cachedRecord: CKRecord?

    init(containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func isAccountAvailable() async throws -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            throw translated(error)
        }
    }

    func fetch() async throws -> Data? {
        guard try await isAccountAvailable() else {
            throw CloudVaultStoreError.accountUnavailable
        }

        let results: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            results = try await database.records(for: [recordID], desiredKeys: [blobKey])
        } catch {
            throw translated(error)
        }
        guard let result = results[recordID] else {
            throw CloudVaultStoreError.malformedResponse
        }

        do {
            let record = try result.get()
            guard let data = record[blobKey] as? Data else {
                throw CloudVaultStoreError.missingBlob
            }
            cachedRecord = record
            return data
        } catch let error as CKError where error.code == .unknownItem {
            cachedRecord = nil
            return nil
        } catch {
            throw translated(error)
        }
    }

    func save(_ data: Data) async throws {
        guard try await isAccountAvailable() else {
            throw CloudVaultStoreError.accountUnavailable
        }

        let record = cachedRecord ?? CKRecord(recordType: recordType, recordID: recordID)
        record[blobKey] = data as CKRecordValue

        do {
            let result = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            guard let saveResult = result.saveResults[recordID] else {
                throw CloudVaultStoreError.malformedResponse
            }
            do {
                cachedRecord = try saveResult.get()
            } catch {
                try handleSaveError(error)
            }
        } catch {
            try handleSaveError(error)
        }
    }

    private func handleSaveError(_ error: Error) throws -> Never {
        if let (serverRecord, serverData) = serverRecordChangedDetails(in: error) {
            cachedRecord = serverRecord
            throw CloudVaultStoreError.serverRecordChanged(serverData: serverData)
        }
        throw translated(error)
    }

    private func serverRecordChangedDetails(in error: Error) -> (CKRecord, Data)? {
        guard let cloudError = error as? CKError else { return nil }
        if cloudError.code == .serverRecordChanged,
           let serverRecord = cloudError.serverRecord,
           let serverData = serverRecord[blobKey] as? Data {
            return (serverRecord, serverData)
        }
        if cloudError.code == .partialFailure,
           let nestedErrors = cloudError.partialErrorsByItemID {
            for nestedError in nestedErrors.values {
                if let details = serverRecordChangedDetails(in: nestedError) {
                    return details
                }
            }
        }
        return nil
    }

    private func translated(_ error: Error) -> Error {
        guard let cloudError = error as? CKError else { return error }
        switch cloudError.code {
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .notAuthenticated,
             .accountTemporarilyUnavailable:
            return CloudVaultStoreError.temporarilyUnavailable
        default:
            return error
        }
    }
}
