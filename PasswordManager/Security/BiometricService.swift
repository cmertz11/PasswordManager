import LocalAuthentication

struct BiometricAvailability: Equatable, Sendable {
    var isAvailable: Bool
    var name: String
    var systemImage: String

    static let unavailable = BiometricAvailability(
        isAvailable: false,
        name: "Biometrics",
        systemImage: "lock"
    )
}

enum BiometricService {
    static func availability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .unavailable
        }

        switch context.biometryType {
        case .faceID:
            return BiometricAvailability(isAvailable: true, name: "Face ID", systemImage: "faceid")
        case .touchID:
            return BiometricAvailability(isAvailable: true, name: "Touch ID", systemImage: "touchid")
        case .opticID:
            return BiometricAvailability(isAvailable: true, name: "Optic ID", systemImage: "opticid")
        case .none:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}
