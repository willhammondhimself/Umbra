import SwiftUI

// MARK: - Conditional View Modifier

extension View {
    /// Applies a modifier only when the condition is true.
    @ViewBuilder
    public func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Glass Card Modifier

public struct GlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Glass Pill Modifier

public struct GlassPillModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.regularMaterial, in: .capsule)
        } else {
            content
                .glassEffect(.regular, in: .capsule)
        }
    }
}

// MARK: - Interactive Glass Modifier

public struct InteractiveGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Prominent Glass Modifier (uses tinted accent for visual weight)

public struct ProminentGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.thickMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.15)), in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Tinted Glass Modifier

public struct TintedGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var tint: Color
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(tint.opacity(0.15))
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - View Extensions

extension View {
    public func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    public func glassPill() -> some View {
        modifier(GlassPillModifier())
    }

    public func interactiveGlass(cornerRadius: CGFloat = 12) -> some View {
        modifier(InteractiveGlassModifier(cornerRadius: cornerRadius))
    }

    public func prominentGlass(cornerRadius: CGFloat = 20) -> some View {
        modifier(ProminentGlassModifier(cornerRadius: cornerRadius))
    }

    public func tintedGlass(_ tint: Color, cornerRadius: CGFloat = 16) -> some View {
        modifier(TintedGlassModifier(tint: tint, cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable Empty State View

public struct TetherEmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let actionLabel: String?
    let action: (() -> Void)?

    public init(
        systemImage: String,
        title: String,
        subtitle: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(subtitle)
        } actions: {
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.tetherPressable)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Reusable Error State View

public struct TetherErrorStateView: View {
    let message: String
    let retryAction: () -> Void

    public init(message: String, retryAction: @escaping () -> Void) {
        self.message = message
        self.retryAction = retryAction
    }

    public var body: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retryAction)
                .buttonStyle(.borderedProminent)
                .buttonStyle(.tetherPressable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Reusable Loading State View

public struct TetherLoadingView: View {
    let message: String

    public init(message: String = "Loading...") {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
