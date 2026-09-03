import Foundation

enum AppConfiguration {
    private static let cloudKitEnabledKey = "PMCloudKitEnabled"
    private static let cloudContainerIdentifierKey = "PMCloudContainerIdentifier"

    static var cloudKitEnabled: Bool {
        if let value = Bundle.main.object(forInfoDictionaryKey: cloudKitEnabledKey) as? Bool {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: cloudKitEnabledKey) as? String {
            return NSString(string: value).boolValue
        }
        return false
    }

    static var cloudContainerIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: cloudContainerIdentifierKey) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.example.PasswordManager"
    }
}
