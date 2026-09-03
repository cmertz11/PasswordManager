import Foundation

#if os(macOS)
import AppKit
#endif

enum SSHLauncher {
    enum Connection: Equatable {
        case destinationURL(URL)
        case customCommand(String)
    }

    static func destinationURL(username: String, host: String) -> URL? {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty,
              !trimmedHost.contains(where: { $0.isWhitespace }),
              !trimmedHost.contains("/"),
              !trimmedHost.contains("@") else { return nil }

        var components = URLComponents()
        components.scheme = "ssh"
        components.user = trimmedUsername.isEmpty ? nil : trimmedUsername
        components.host = trimmedHost
        return components.url
    }

    static func connection(username: String, host: String, customCommand: String) -> Connection? {
        if !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .customCommand(customCommand)
        }

        guard let url = destinationURL(username: username, host: host) else { return nil }
        return .destinationURL(url)
    }

    #if os(macOS)
    @MainActor
    static func openTerminal(username: String, host: String, customCommand: String) -> Bool {
        guard let connection = connection(
            username: username,
            host: host,
            customCommand: customCommand
        ) else { return false }

        switch connection {
        case .destinationURL(let url):
            return NSWorkspace.shared.open(url)
        case .customCommand(let command):
            return runInTerminal(command)
        }
    }

    private static func runInTerminal(_ command: String) -> Bool {
        let source = """
        tell application "Terminal"
            activate
            do script \(appleScriptLiteral(command))
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return false }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    static func appleScriptLiteral(_ value: String) -> String {
        var segments = [String]()
        var current = ""

        func quoted(_ segment: String) -> String {
            let escaped = segment
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }

        for character in value {
            switch character {
            case "\n":
                segments.append(quoted(current))
                segments.append("linefeed")
                current = ""
            case "\r":
                segments.append(quoted(current))
                segments.append("return")
                current = ""
            default:
                current.append(character)
            }
        }
        segments.append(quoted(current))
        return segments.joined(separator: " & ")
    }
    #endif
}
