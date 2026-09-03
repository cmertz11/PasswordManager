import Foundation
import XCTest
@testable import PasswordManager

final class VaultPayloadMergeTests: XCTestCase {
    func testNewerEditWins() {
        let id = UUID()
        let older = Credential(
            id: id,
            name: "Older",
            updatedAt: Date(timeIntervalSince1970: 100),
            revision: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let newer = Credential(
            id: id,
            name: "Newer",
            updatedAt: Date(timeIntervalSince1970: 200),
            revision: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        let merged = VaultPayload(credentials: [older]).merged(with: VaultPayload(credentials: [newer]))
        XCTAssertEqual(merged.credentials, [newer])
    }

    func testNewerDeletionWins() {
        let credential = Credential(
            name: "Delete me",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let tombstone = DeletionTombstone(
            credentialID: credential.id,
            deletedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = VaultPayload(credentials: [credential]).merged(
            with: VaultPayload(tombstones: [tombstone])
        )
        XCTAssertTrue(merged.credentials.isEmpty)
        XCTAssertEqual(merged.tombstones, [tombstone])
    }

    func testNewerEditResurrectsOlderDeletion() {
        let id = UUID()
        let tombstone = DeletionTombstone(
            credentialID: id,
            deletedAt: Date(timeIntervalSince1970: 100)
        )
        let credential = Credential(
            id: id,
            name: "Restored",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = VaultPayload(tombstones: [tombstone]).merged(
            with: VaultPayload(credentials: [credential])
        )
        XCTAssertEqual(merged.credentials, [credential])
        XCTAssertTrue(merged.tombstones.isEmpty)
    }
}
