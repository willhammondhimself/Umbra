import SwiftUI

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
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
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
                .glassEffect(in: .capsule)
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

// MARK: - Prominent Glass Modifier

public struct ProminentGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.thickMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
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
