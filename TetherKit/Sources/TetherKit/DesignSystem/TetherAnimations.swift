import SwiftUI

// MARK: - Spring Presets

extension Animation {
    public static let tetherSpring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    public static let tetherQuick = Animation.spring(response: 0.25, dampingFraction: 0.8)
    public static let tetherBounce = Animation.spring(response: 0.5, dampingFraction: 0.6)
}

// MARK: - Reduce-Motion-Aware Animation Wrapper

/// Wraps any spring animation so it is suppressed when the user has enabled
/// Reduce Motion in System Settings > Accessibility > Display.
public struct MotionAwareValueModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animation: Animation
    var value: V

    public func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Apply a Tether spring animation that is automatically disabled when
    /// the user enables Reduce Motion.
    public func withTetherAnimation<V: Equatable>(_ animation: Animation = .tetherSpring, value: V) -> some View {
        modifier(MotionAwareValueModifier(animation: animation, value: value))
    }
}

// MARK: - Pressable Button Style (spring scale on press)

public struct TetherPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat

    public init(scale: CGFloat = 0.96) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .animation(.tetherQuick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TetherPressableButtonStyle {
    public static var tetherPressable: TetherPressableButtonStyle { .init() }
    public static func tetherPressable(scale: CGFloat) -> TetherPressableButtonStyle { .init(scale: scale) }
}

// MARK: - State Transitions
//
// Note: AnyTransition does not have access to @Environment, so reduce-motion
// gating must be applied at the call site using `withTetherAnimation` or by
// wrapping `withAnimation` in a reduce-motion check. These transitions provide
// the animation definition only; call sites should prefer:
//   `withAnimation(reduceMotion ? .none : .tetherQuick) { ... }`

extension AnyTransition {
    public static var tetherFade: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97)).animation(.tetherQuick)
    }

    public static var tetherSlideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ).animation(.tetherSpring)
    }
}
