import Foundation
import XCTest
@testable import PasswordManager

final class CredentialTests: XCTestCase {
    func testLegacyCredentialWithoutTypeDecodesAsWebsite() throws {
        let original = Credential(
            name: "Existing Login",
            username: "person@example.com",
            password: "secret",
            website: "example.com"
        )
        let encoded = try JSONEncoder().encode(original)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "kind")
        legacyObject.removeValue(forKey: "allowedPasswordSymbols")
        legacyObject.removeValue(forKey: "sshHost")
        legacyObject.removeValue(forKey: "sshCommand")
        legacyObject.removeValue(forKey: "apiKey")
        legacyObject.removeValue(forKey: "apiEndpoint")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(Credential.self, from: legacyData)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .website)
        XCTAssertEqual(decoded.allowedPasswordSymbols, "")
        XCTAssertEqual(decoded.sshHost, "")
        XCTAssertEqual(decoded.sshCommand, "")
        XCTAssertEqual(decoded.apiKey, "")
        XCTAssertEqual(decoded.apiEndpoint, "")
    }

    func testSSHCredentialRoundTripPreservesConnectionConfiguration() throws {
        let original = Credential(
            name: "Home Server",
            username: "admin",
            password: "secret",
            kind: .ssh,
            sshHost: "192.168.1.42",
            sshCommand: "ssh -J gateway admin@192.168.1.42"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Credential.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testWebsiteCredentialRoundTripPreservesPerSiteSymbols() throws {
        let fidelitySymbols = "!@$%^()-_+=|\\:;',.?/~"
        let original = Credential(
            name: "Fidelity",
            username: "investor",
            password: "secret",
            website: "fidelity.com",
            allowedPasswordSymbols: fidelitySymbols
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Credential.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.allowedPasswordSymbols, fidelitySymbols)
    }

    func testAPIKeyCredentialRoundTripPreservesSecretAndEndpoint() throws {
        let original = Credential(
            name: "Example Developer API",
            username: "production",
            kind: .apiKey,
            apiKey: "example-secret-token",
            apiEndpoint: "https://api.example.com/v1",
            notes: "Created for the desktop client"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Credential.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }
}
