import CommonCrypto
import Foundation

enum PasswordKDFError: Error, Equatable {
    case invalidParameters
    case derivationFailed(Int32)
}

enum PasswordKDF {
    static let defaultIterations = 600_000
    static let maximumSupportedIterations = 10_000_000
    static let saltByteCount = 16
    static let keyByteCount = 32

    static func deriveKey(password: String, parameters: KDFParameters) throws -> Data {
        try validate(parameters)

        var passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: keyByteCount)
        defer {
            _ = passwordBytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }

        let status: Int32 = passwordBytes.withUnsafeBufferPointer { passwordBuffer in
            parameters.salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: passwordBuffer.count) { $0 },
                    passwordBuffer.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    saltBuffer.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(parameters.iterations),
                    &derived,
                    derived.count
                )
            }
        }

        guard status == kCCSuccess else {
            throw PasswordKDFError.derivationFailed(status)
        }
        return Data(derived)
    }

    static func makeParameters(iterations: Int = defaultIterations) throws -> KDFParameters {
        let parameters = KDFParameters(
            algorithm: KDFParameters.supportedAlgorithm,
            salt: try SecureRandom.bytes(count: saltByteCount),
            iterations: iterations
        )
        try validate(parameters)
        return parameters
    }

    static func validate(_ parameters: KDFParameters) throws {
        guard parameters.algorithm == KDFParameters.supportedAlgorithm,
              parameters.salt.count == saltByteCount,
              parameters.iterations >= defaultIterations,
              parameters.iterations <= maximumSupportedIterations else {
            throw PasswordKDFError.invalidParameters
        }
    }
}
