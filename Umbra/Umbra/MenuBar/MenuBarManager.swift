import AppKit
import SwiftUI
import UmbraKit

@MainActor
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func setup() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Umbra")
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func updateIcon(isInSession: Bool) {
        let symbolName = isInSession ? "timer.circle.fill" : "timer"
        statusItem?.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Umbra")

        // Sync status badge via accessory image
        let syncManager = SyncManager.shared
        if !syncManager.isOnline {
            statusItem?.button?.appearsDisabled = true
        } else {
            statusItem?.button?.appearsDisabled = false
        }
    }
}
