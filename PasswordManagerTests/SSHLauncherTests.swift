import Foundation
import XCTest
@testable import PasswordManager

final class SSHLauncherTests: XCTestCase {
    func testDestinationURLIncludesUsernameAndIPAddress() {
        let url = SSHLauncher.destinationURL(
            username: " admin ",
            host: " 192.168.1.42 "
        )

        XCTAssertEqual(url?.absoluteString, "ssh://admin@192.168.1.42")
    }

    func testDestinationURLCanOmitUsername() {
        let url = SSHLauncher.destinationURL(username: "", host: "server.example.com")

        XCTAssertEqual(url?.absoluteString, "ssh://server.example.com")
    }

    func testDestinationURLRejectsCommandLikeHosts() {
        XCTAssertNil(SSHLauncher.destinationURL(username: "admin", host: "server.example.com /tmp"))
        XCTAssertNil(SSHLauncher.destinationURL(username: "admin", host: "admin@server.example.com"))
        XCTAssertNil(SSHLauncher.destinationURL(username: "admin", host: ""))
    }

    func testCustomCommandTakesPrecedenceWithoutCombiningUsernameAndHost() {
        let command = "ssh -J bastion -p 2222 -L 5432:db.internal:5432 deploy@service.internal"

        let connection = SSHLauncher.connection(
            username: "must-not-be-added",
            host: "must-not-be-added.example.com",
            customCommand: command
        )

        XCTAssertEqual(connection, .customCommand(command))
    }

    func testBlankCustomCommandFallsBackToDestinationURL() {
        let connection = SSHLauncher.connection(
            username: "admin",
            host: "server.example.com",
            customCommand: "  \n"
        )

        XCTAssertEqual(connection, .destinationURL(URL(string: "ssh://admin@server.example.com")!))
    }

    func testCustomCommandCanBeUsedWithoutUsernameOrHost() {
        let command = "ssh production"

        XCTAssertEqual(
            SSHLauncher.connection(username: "", host: "", customCommand: command),
            .customCommand(command)
        )
    }

    #if os(macOS)
    func testComplexCommandRoundTripsThroughTerminalAppleScriptLiteral() throws {
        let command = #"ssh -o ProxyCommand="ssh -W %h:%p jump" 'deploy user'@service.internal \"#
            + "\nprintf '%s' \"$SSH_AUTH_SOCK\""
        let script = try XCTUnwrap(NSAppleScript(source: "return \(SSHLauncher.appleScriptLiteral(command))"))
        var error: NSDictionary?

        let result = script.executeAndReturnError(&error)

        XCTAssertNil(error)
        XCTAssertEqual(result.stringValue, command)
    }
    #endif
}
