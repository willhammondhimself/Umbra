import SwiftUI
import UmbraKit

struct PostSessionSummaryView: View {
    let session: Session
    let streak: Int
    var onNewSession: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.umbraFocused)

            Text("Session Complete")
                .font(.title)
                .fontWeight(.bold)

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 16) {
                summaryCard(
                    icon: "clock",
                    label: "Total Time",
                    value: session.formattedDuration,
                    color: Color.umbraNeutral
                )

                summaryCard(
                    icon: "eye",
                    label: "Focused",
                    value: session.formattedFocused,
                    color: Color.umbraFocused
                )

                summaryCard(
                    icon: "percent",
                    label: "Focus Rate",
                    value: String(format: "%.0f%%", session.focusPercentage),
                    color: session.focusPercentage >= 80 ? Color.umbraFocused : Color.umbraPaused
                )

                summaryCard(
                    icon: "exclamationmark.triangle",
                    label: "Distractions",
                    value: "\(session.distractionCount)",
                    color: session.distractionCount == 0 ? Color.umbraFocused : Color.umbraDistracted
                )
            }

            // Streak
            if streak > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.umbraStreak)
                    Text("\(streak) day streak!")
                        .font(.headline)
                        .foregroundStyle(Color.umbraStreak)
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 8)

            // Actions
            HStack(spacing: 12) {
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.escape, modifiers: [])

                Button("Start New Session") {
                    onNewSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.top, 44)
        .padding([.bottom, .leading, .trailing], 28)
        .frame(width: 480, height: 400)
        .glassEffect(in: .rect(cornerRadius: UmbraRadius.card))
    }

    @ViewBuilder
    private func summaryCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: UmbraRadius.button))
    }
}
