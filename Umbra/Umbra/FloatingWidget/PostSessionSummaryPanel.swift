import AppKit
import SwiftUI

/// Standalone popup panel for post-session summary.
/// Centered on screen with Liquid Glass background.
@MainActor
final class PostSessionSummaryPanel: NSPanel {

    init(contentView: some View) {
        let initialRect = NSRect(x: 0, y: 0, width: 480, height: 400)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .modalPanel
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = initialRect
        self.contentView = hostingView

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - initialRect.width / 2
            let y = screenFrame.midY - initialRect.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
