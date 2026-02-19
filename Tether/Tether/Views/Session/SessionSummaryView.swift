import SwiftUI
import TetherKit

struct SessionSummaryView: View {
    let session: Session
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(TetherFont.iconHeroSmall)
                .foregroundStyle(Color.tetherFocused)

            Text("Session Complete")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Summary stats
            HStack(spacing: 40) {
                SummaryStatView(
                    label: "Total Time",
                    value: session.formattedDuration,
                    icon: "clock"
                )

                SummaryStatView(
                    label: "Focused Time",
                    value: session.formattedFocused,
                    icon: "eye"
                )

                SummaryStatView(
                    label: "Focus Rate",
                    value: String(format: "%.0f%%", session.focusPercentage),
                    icon: "percent"
                )

                SummaryStatView(
                    label: "Distractions",
                    value: "\(session.distractionCount)",
                    icon: "exclamationmark.triangle"
                )
            }

            Spacer()

            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .buttonStyle(.tetherPressable)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct SummaryStatView: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassCard(cornerRadius: TetherRadius.button)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
