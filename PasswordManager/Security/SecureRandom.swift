import Foundation
import Security

enum SecureRandomError: Error, Equatable {
    case invalidCount
    case generationFailed(OSStatus)
    case invalidUpperBound
}

enum SecureRandom {
    static func bytes(count: Int) throws -> Data {
        guard count >= 0 else { throw SecureRandomError.invalidCount }
        guard count > 0 else { return Data() }

        var result = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, result.count, &result)
        guard status == errSecSuccess else {
            throw SecureRandomError.generationFailed(status)
        }
        return Data(result)
    }

    static func uniformIndex(upperBound: Int) throws -> Int {
        guard upperBound > 0, upperBound <= 255 else {
            throw SecureRandomError.invalidUpperBound
        }

        let acceptanceLimit = 256 - (256 % upperBound)
        while true {
            let value = try bytes(count: 1)[0]
            if Int(value) < acceptanceLimit {
                return Int(value) % upperBound
            }
        }
    }
}
