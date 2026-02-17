import Foundation
import AppKit
import CoreGraphics

@MainActor
final class AppMonitor {
    private var pollTask: Task<Void, Never>?
    private var lastBundleId: String = ""
    private var idleThresholdSeconds: TimeInterval = 300 // 5 minutes

    typealias AppSwitchHandler = (String, String) -> Void

    func startMonitoring(onAppSwitch: @escaping AppSwitchHandler) {
        lastBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.poll(onAppSwitch: onAppSwitch)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll(onAppSwitch: AppSwitchHandler) {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = frontmost.bundleIdentifier ?? ""
        let appName = frontmost.localizedName ?? "Unknown"

        // Detect app switch
        if bundleId != lastBundleId {
            lastBundleId = bundleId
            onAppSwitch(appName, bundleId)
        }
    }

    /// Returns seconds since last user input event (keyboard or mouse)
    var idleTime: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
    }

    var isIdle: Bool {
        idleTime >= idleThresholdSeconds
    }
}
