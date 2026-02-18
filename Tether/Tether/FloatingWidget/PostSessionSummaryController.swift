import AppKit
import SwiftUI
import TetherKit
import Foundation

/// Manages the post-session summary popup lifecycle.
@MainActor
final class PostSessionSummaryController {
    static let shared = PostSessionSummaryController()

    private var panel: PostSessionSummaryPanel?

    private init() {}

    func show(session: Session) {
        dismiss()

        let streak = currentStreak()
        let summaryView = PostSessionSummaryView(
            session: session,
            streak: streak,
            onNewSession: { [weak self] in
                self?.dismiss()
                SessionManager.shared.dismissSummary()
                SessionManager.shared.startSession()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
                SessionManager.shared.dismissSummary()
            }
        )

        let newPanel = PostSessionSummaryPanel(contentView: summaryView)
        newPanel.alphaValue = 0
        newPanel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1
        }

        panel = newPanel
    }

    func dismiss() {
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        })
    }

    private func currentStreak() -> Int {
        do {
            let sessions = try DatabaseManager.shared.fetchSessions(limit: 90)
                .filter { $0.isComplete }
            guard !sessions.isEmpty else { return 0 }

            var streak = 0
            let calendar = Calendar.current
            var checkDate = calendar.startOfDay(for: Date())

            for _ in 0..<90 {
                let hasSession = sessions.contains { session in
                    calendar.isDate(session.startTime, inSameDayAs: checkDate)
                }
                if hasSession {
                    streak += 1
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                } else {
                    break
                }
            }
            return streak
        } catch {
            return 0
        }
    }

}
