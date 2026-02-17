import SwiftUI

// MARK: - Spring Presets

extension Animation {
    public static let tetherSpring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    public static let tetherQuick = Animation.spring(response: 0.25, dampingFraction: 0.8)
    public static let tetherBounce = Animation.spring(response: 0.5, dampingFraction: 0.6)
}

// MARK: - Reduce-Motion-Aware Wrapper

public struct MotionAwareModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animation: Animation

    public func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(animation, value: true)
        }
    }
}

extension View {
    public func tetherAnimation(_ animation: Animation = .tetherSpring) -> some View {
        modifier(MotionAwareModifier(animation: animation))
    }

    public func withTetherAnimation<V: Equatable>(_ animation: Animation = .tetherSpring, value: V) -> some View {
        self.animation(animation, value: value)
    }
}
