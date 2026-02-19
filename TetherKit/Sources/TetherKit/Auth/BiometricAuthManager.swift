import Foundation
import LocalAuthentication

@MainActor
@Observable
public final class BiometricAuthManager {
    public static let shared = BiometricAuthManager()

    public private(set) var isBiometricAvailable = false
    public private(set) var biometricType: LABiometryType = .none

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "biometricUnlockEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "biometricUnlockEnabled") }
    }

    private init() {
        checkAvailability()
    }

    public func checkAvailability() {
        let context = LAContext()
        var error: NSError?
        isBiometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometricType = context.biometryType
    }

    public var biometricName: String {
        switch biometricType {
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        case .none: "Biometric"
        @unknown default: "Biometric"
        }
    }

    public func authenticate(reason: String = "Unlock Tether") async -> Bool {
        guard isBiometricAvailable else { return true }
        guard isEnabled else { return true }

        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            TetherLogger.auth.error("Biometric auth failed: \(error.localizedDescription)")
            // Fall back to device passcode
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
            } catch {
                return false
            }
        }
    }

    public func authenticateForSensitiveAction(reason: String) async -> Bool {
        let context = LAContext()

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
