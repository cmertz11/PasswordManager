import Foundation
import LocalAuthentication
import Security

enum KeychainServiceError: Error, Equatable {
    case biometryUnavailable
    case accessControlCreationFailed
    case itemNotFound
    case cancelled
    case unexpectedStatus(OSStatus)
    case malformedItem
}

struct KeychainService: Sendable {
    private let service = "\(AppConfiguration.bundleIdentifier).vault-key"

    func storeVaultKey(_ keyData: Data, vaultID: UUID) throws {
        guard BiometricService.availability().isAvailable else {
            throw KeychainServiceError.biometryUnavailable
        }

        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            throw KeychainServiceError.accessControlCreationFailed
        }

        try deleteVaultKey(vaultID: vaultID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID.uuidString.lowercased(),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: keyData
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    func retrieveVaultKey(vaultID: UUID, prompt: String) throws -> Data {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Master Password"
        context.localizedReason = prompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID.uuidString.lowercased(),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == CryptoService.vaultKeyByteCount else {
                throw KeychainServiceError.malformedItem
            }
            return data
        case errSecItemNotFound:
            throw KeychainServiceError.itemNotFound
        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainServiceError.cancelled
        default:
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    func deleteVaultKey(vaultID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID.uuidString.lowercased(),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
}
