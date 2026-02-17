import AppKit
import SwiftUI

/// NSPanel subclass for the always-on-top floating session widget.
/// Non-activating so it doesn't steal focus from the user's work.
@MainActor
final class FloatingWidgetPanel: NSPanel {

    init(contentView: some View) {
        let initialRect = NSRect(x: 0, y: 0, width: 220, height: 48)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        becomesKeyOnlyIfNeeded = true

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = initialRect
        self.contentView = hostingView
    }

    // Allow the panel to receive mouse events for hover without becoming key
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
