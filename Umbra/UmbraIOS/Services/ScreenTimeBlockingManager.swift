import Foundation
import FamilyControls
import ManagedSettings

/// Manages Screen Time API blocking on iOS.
/// Requires FamilyControls entitlement and user authorization.
@MainActor
@Observable
final class ScreenTimeBlockingManager {
    static let shared = ScreenTimeBlockingManager()

    private(set) var isAuthorized = false
    private(set) var isActive = false
    private let store = ManagedSettingsStore()
    var selectedApps = FamilyActivitySelection()

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Blocking

    func activate() {
        guard isAuthorized else { return }
        let applications = selectedApps.applicationTokens
        let categories = selectedApps.categoryTokens

        if !applications.isEmpty || !categories.isEmpty {
            store.shield.applications = applications.isEmpty ? nil : applications
            store.shield.applicationCategories = categories.isEmpty
                ? nil
                : .specific(categories)
            isActive = true
        }
    }

    func deactivate() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isActive = false
    }

    // MARK: - Selection

    func updateSelection(_ selection: FamilyActivitySelection) {
        selectedApps = selection
    }
}
