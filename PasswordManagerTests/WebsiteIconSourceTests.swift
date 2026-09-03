import XCTest
@testable import PasswordManager

final class WebsiteIconSourceTests: XCTestCase {
    func testCreatesDirectHTTPSIconCandidatesFromWebsite() {
        let urls = WebsiteIconSource.candidateURLs(for: "https://example.com/account/login?source=test")

        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://example.com/apple-touch-icon.png",
            "https://example.com/favicon.ico"
        ])
    }

    func testAddsHTTPSAndPreservesCustomPort() {
        let urls = WebsiteIconSource.candidateURLs(for: "example.com:8443/login")

        XCTAssertEqual(urls.first?.absoluteString, "https://example.com:8443/apple-touch-icon.png")
    }

    func testUpgradesExplicitHTTPToHTTPS() {
        let urls = WebsiteIconSource.candidateURLs(for: "http://example.com")

        XCTAssertEqual(urls.last?.absoluteString, "https://example.com/favicon.ico")
    }

    func testRejectsUnsupportedOrMalformedWebsiteAddresses() {
        XCTAssertTrue(WebsiteIconSource.candidateURLs(for: "").isEmpty)
        XCTAssertTrue(WebsiteIconSource.candidateURLs(for: "ftp://example.com").isEmpty)
        XCTAssertTrue(WebsiteIconSource.candidateURLs(for: "https://").isEmpty)
    }
}
