import Foundation
import AppKit
import SwiftUI
import Combine
import os
import TetherKit

@MainActor
@Observable
final class BlockingManager {
    static let shared = BlockingManager()

    private(set) var isActive = false
    private(set) var blocklistItems: [BlocklistItem] = []
    private(set) var sessionExemptions: Set<String> = [] // Bundle IDs exempted for current session

    private var workspaceObserver: Any?
    private var overlayWindows: [NSWindow] = []

    // Current block state
    private(set) var currentBlockedApp: String?
    private(set) var currentBlockMode: BlocklistItem.BlockMode?
    private(set) var timedLockCountdown: Int = 0
    private var countdownTask: Task<Void, Never>?

    init() {
        loadBlocklist()
    }

    // MARK: - Blocklist Management

    func loadBlocklist() {
        do {
            blocklistItems = try DatabaseManager.shared.fetchBlocklistItems()
        } catch {
            TetherLogger.blocking.error("Failed to load blocklist: \(error.localizedDescription)")
        }
    }

    func addItem(_ item: BlocklistItem) {
        var mutable = item
        do {
            try DatabaseManager.shared.saveBlocklistItem(&mutable)
            loadBlocklist()
            updateSessionManagerBlocklist()
            syncSafariRules()
        } catch {
            TetherLogger.blocking.error("Failed to save blocklist item: \(error.localizedDescription)")
        }
    }

    func removeItem(_ item: BlocklistItem) {
        do {
            try DatabaseManager.shared.deleteBlocklistItem(item)
            loadBlocklist()
            updateSessionManagerBlocklist()
            syncSafariRules()
        } catch {
            TetherLogger.blocking.error("Failed to delete blocklist item: \(error.localizedDescription)")
        }
    }

    func toggleItem(_ item: BlocklistItem) {
        var updated = item
        updated.isEnabled.toggle()
        do {
            try DatabaseManager.shared.saveBlocklistItem(&updated)
            loadBlocklist()
            updateSessionManagerBlocklist()
            syncSafariRules()
        } catch {
            TetherLogger.blocking.error("Failed to toggle blocklist item: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Exemptions

    func addExemption(bundleId: String) {
        sessionExemptions.insert(bundleId)
    }

    func clearExemptions() {
        sessionExemptions.removeAll()
    }

    // MARK: - Blocking Activation

    func activate() {
        guard !isActive else { return }
        isActive = true
        updateSessionManagerBlocklist()
        startObserving()
        SharedBlocklistStore.shared.setSessionActive(true)
        syncSafariRules()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        stopObserving()
        dismissOverlay()
        clearExemptions()
        SharedBlocklistStore.shared.setSessionActive(false)
        syncSafariRules()
    }

    // MARK: - App Launch Observation

    private func startObserving() {
        let wsnc = NSWorkspace.shared.notificationCenter
        workspaceObserver = wsnc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleAppActivation(app)
        }
    }

    private func stopObserving() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    private func handleAppActivation(_ app: NSRunningApplication) {
        guard isActive else { return }
        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? "Unknown"

        // Skip if it's Tether itself
        if bundleId == Bundle.main.bundleIdentifier { return }

        // Skip if exempted for this session
        if sessionExemptions.contains(bundleId) { return }

        // Check blocklist
        guard let blockedItem = blocklistItems.first(where: {
            $0.isEnabled && $0.bundleId == bundleId
        }) else { return }

        currentBlockedApp = appName
        currentBlockMode = blockedItem.blockMode

        switch blockedItem.blockMode {
        case .softWarn:
            showOverlay(appName: appName, mode: .softWarn)

        case .hardBlock:
            app.terminate()
            showOverlay(appName: appName, mode: .hardBlock)

        case .timedLock:
            app.terminate()
            startTimedLock(appName: appName)
        }
    }

    // MARK: - Overlay

    private func showOverlay(appName: String, mode: BlocklistItem.BlockMode) {
        dismissOverlay()

        guard let screen = NSScreen.main else { return }

        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: BlockOverlayView(
            appName: appName,
            mode: mode,
            countdown: mode == .timedLock ? timedLockCountdown : nil,
            onDismiss: { [weak self] in
                self?.dismissOverlay()
            },
            onOverride: { [weak self] reason in
                self?.handleOverride(reason: reason)
            }
        ))
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        overlayWindows.append(window)
    }

    func updateOverlay() {
        guard let appName = currentBlockedApp, let mode = currentBlockMode else { return }
        dismissOverlay()
        showOverlay(appName: appName, mode: mode)
    }

    func dismissOverlay() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        countdownTask?.cancel()
        currentBlockedApp = nil
        currentBlockMode = nil
    }

    // MARK: - Timed Lock

    private func startTimedLock(appName: String) {
        timedLockCountdown = 10
        showOverlay(appName: appName, mode: .timedLock)

        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while let self = self, self.timedLockCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.timedLockCountdown -= 1
                self.updateOverlay()
            }
        }
    }

    // MARK: - Override

    private func handleOverride(reason: String) {
        // Log override event
        if let sessionManager = Optional(SessionManager.shared),
           sessionManager.state == .running || sessionManager.state == .paused {
            // The override is logged as metadata
            TetherLogger.blocking.info("Block override: \(reason)")
        }
        dismissOverlay()
    }

    // MARK: - Helpers

    private func updateSessionManagerBlocklist() {
        let bundleIds = Set(
            blocklistItems
                .filter { $0.isEnabled && $0.bundleId != nil }
                .compactMap { $0.bundleId }
        )
        SessionManager.shared.distractingBundleIds = bundleIds
    }

    /// Sync current blocklist rules to Safari extension via shared app group container.
    private func syncSafariRules() {
        SharedBlocklistStore.shared.writeRules(blocklistItems)
    }
}
