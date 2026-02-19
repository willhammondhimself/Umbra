import SwiftUI
import TetherKit

struct BlockOverlayView: View {
    let appName: String
    let mode: BlocklistItem.BlockMode
    let countdown: Int?
    var onDismiss: () -> Void
    var onOverride: (String) -> Void

    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var overrideReason = ""
    @State private var showReasonField = false
    @State private var holdTask: Task<Void, Never>?

    private let holdDuration: TimeInterval = 3.0

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)

                Text("\(appName) is blocked")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Stay focused on your current task.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))

                // Mode-specific content
                switch mode {
                case .softWarn:
                    softWarnContent

                case .hardBlock:
                    hardBlockContent

                case .timedLock:
                    timedLockContent
                }
            }
            .padding(40)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(appName) is blocked. Stay focused on your current task.")
        }
    }

    // MARK: - Soft Warn

    private var softWarnContent: some View {
        VStack(spacing: 16) {
            Button("Stay Focused") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)

            Button("Continue Anyway") {
                onOverride("soft-override")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    // MARK: - Hard Block

    private var hardBlockContent: some View {
        VStack(spacing: 16) {
            if showReasonField {
                TextField("Why do you need this app?", text: $overrideReason)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                overrideButton
            } else {
                Text("Hold to override")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                overrideButton
            }
        }
    }

    // MARK: - Timed Lock

    private var timedLockContent: some View {
        VStack(spacing: 16) {
            if let countdown, countdown > 0 {
                Text("Override available in \(countdown)s")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            } else {
                if showReasonField {
                    TextField("Why do you need this app?", text: $overrideReason)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }

                overrideButton
            }
        }
    }

    // MARK: - Override Button

    private var overrideButton: some View {
        ZStack {
            // Progress ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)
                .frame(width: 80, height: 80)

            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: holdProgress)

            Text("Hold")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Override block")
        .accessibilityHint("Press and hold for 3 seconds to override the block")
        .accessibilityValue(holdProgress > 0 ? "\(Int(holdProgress * 100)) percent" : "Not started")
        .gesture(
            LongPressGesture(minimumDuration: holdDuration)
                .onChanged { _ in
                    startHold()
                }
                .onEnded { _ in
                    completeOverride()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    cancelHold()
                }
        )
    }

    private func startHold() {
        guard !isHolding else { return }
        isHolding = true
        holdProgress = 0

        holdTask = Task { @MainActor in
            let steps = 30
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(Int(holdDuration * 1000) / steps))
                guard !Task.isCancelled else { return }
                holdProgress = CGFloat(i) / CGFloat(steps)
            }
        }
    }

    private func cancelHold() {
        isHolding = false
        holdTask?.cancel()
        withAnimation { holdProgress = 0 }
    }

    private func completeOverride() {
        isHolding = false
        holdTask?.cancel()
        holdProgress = 1.0

        if !showReasonField {
            showReasonField = true
            withAnimation { holdProgress = 0 }
        } else {
            let reason = overrideReason.isEmpty ? "No reason given" : overrideReason
            onOverride(reason)
        }
    }
}
