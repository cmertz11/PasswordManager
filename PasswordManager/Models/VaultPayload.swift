import Foundation

struct DeletionTombstone: Codable, Hashable, Sendable {
    var credentialID: UUID
    var deletedAt: Date
    var revision: UUID

    init(credentialID: UUID, deletedAt: Date = Date(), revision: UUID = UUID()) {
        self.credentialID = credentialID
        self.deletedAt = VaultTimestamp.normalized(deletedAt)
        self.revision = revision
    }
}

struct VaultPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var credentials: [Credential]
    var tombstones: [DeletionTombstone]

    init(
        schemaVersion: Int = VaultPayload.currentSchemaVersion,
        credentials: [Credential] = [],
        tombstones: [DeletionTombstone] = []
    ) {
        self.schemaVersion = schemaVersion
        self.credentials = credentials
        self.tombstones = tombstones
    }

    mutating func upsert(_ credential: Credential) {
        credentials.removeAll { $0.id == credential.id }
        tombstones.removeAll { $0.credentialID == credential.id }
        credentials.append(credential)
    }

    mutating func delete(credentialID: UUID, at date: Date = Date()) {
        credentials.removeAll { $0.id == credentialID }
        tombstones.removeAll { $0.credentialID == credentialID }
        tombstones.append(DeletionTombstone(credentialID: credentialID, deletedAt: date))
    }

    func merged(with other: VaultPayload) -> VaultPayload {
        var bestCredentials: [UUID: Credential] = [:]
        var bestTombstones: [UUID: DeletionTombstone] = [:]

        for credential in credentials + other.credentials {
            guard let existing = bestCredentials[credential.id] else {
                bestCredentials[credential.id] = credential
                continue
            }
            if Self.isNewer(credential, than: existing) {
                bestCredentials[credential.id] = credential
            }
        }

        for tombstone in tombstones + other.tombstones {
            guard let existing = bestTombstones[tombstone.credentialID] else {
                bestTombstones[tombstone.credentialID] = tombstone
                continue
            }
            if Self.isNewer(tombstone, than: existing) {
                bestTombstones[tombstone.credentialID] = tombstone
            }
        }

        for (id, tombstone) in bestTombstones {
            guard let credential = bestCredentials[id] else { continue }
            if tombstone.deletedAt > credential.updatedAt ||
                (tombstone.deletedAt == credential.updatedAt && tombstone.revision.uuidString > credential.revision.uuidString) {
                bestCredentials[id] = nil
            } else {
                bestTombstones[id] = nil
            }
        }

        return VaultPayload(
            schemaVersion: max(schemaVersion, other.schemaVersion),
            credentials: bestCredentials.values.sorted(by: Self.stableCredentialOrder),
            tombstones: bestTombstones.values.sorted {
                if $0.deletedAt != $1.deletedAt { return $0.deletedAt < $1.deletedAt }
                return $0.credentialID.uuidString < $1.credentialID.uuidString
            }
        )
    }

    private static func isNewer(_ lhs: Credential, than rhs: Credential) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.revision.uuidString > rhs.revision.uuidString
    }

    private static func isNewer(_ lhs: DeletionTombstone, than rhs: DeletionTombstone) -> Bool {
        if lhs.deletedAt != rhs.deletedAt { return lhs.deletedAt > rhs.deletedAt }
        return lhs.revision.uuidString > rhs.revision.uuidString
    }

    private static func stableCredentialOrder(_ lhs: Credential, _ rhs: Credential) -> Bool {
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
