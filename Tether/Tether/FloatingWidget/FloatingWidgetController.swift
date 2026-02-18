import AppKit
import SwiftUI
import Foundation

/// Manages the floating session widget panel lifecycle.
/// Shows during active sessions, hides when session ends.
@MainActor
final class FloatingWidgetController {
    static let shared = FloatingWidgetController()

    private var panel: FloatingWidgetPanel?

    private let positionXKey = "FloatingWidgetPositionX"
    private let positionYKey = "FloatingWidgetPositionY"

    private init() {}

    func showWidget() {
        guard panel == nil else { return }

        let widgetView = FloatingWidgetView()
        let newPanel = FloatingWidgetPanel(contentView: widgetView)

        // Restore saved position or default to top-right
        let x = UserDefaults.standard.object(forKey: positionXKey) as? CGFloat
            ?? (NSScreen.main?.visibleFrame.maxX ?? 1200) - 240
        let y = UserDefaults.standard.object(forKey: positionYKey) as? CGFloat
            ?? (NSScreen.main?.visibleFrame.maxY ?? 800) - 80

        newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        newPanel.alphaValue = 0
        newPanel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1
        }

        panel = newPanel
    }

    func hideWidget() {
        guard let panel else { return }
        savePosition()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel?.orderOut(nil)
                self?.panel = nil
            }
        })
    }

    private func savePosition() {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set(frame.origin.x, forKey: positionXKey)
        UserDefaults.standard.set(frame.origin.y, forKey: positionYKey)
    }

}
