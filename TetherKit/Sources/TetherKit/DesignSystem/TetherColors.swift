import SwiftUI

// MARK: - Semantic Color Tokens

extension Color {
    public static let tetherFocused = Color.green
    public static let tetherDistracted = Color.red
    public static let tetherPaused = Color.orange
    public static let tetherIdle = Color.secondary
    public static let tetherStreak = Color.orange
    public static let tetherPositive = Color.green
    public static let tetherWarning = Color.yellow
    public static let tetherNeutral = Color.blue
}

// MARK: - Session Status Color

extension Color {
    public static func forSessionStatus(_ isDistracted: Bool, isPaused: Bool) -> Color {
        if isPaused { return .tetherPaused }
        if isDistracted { return .tetherDistracted }
        return .tetherFocused
    }
}

// MARK: - Glass Surface Colors

extension ShapeStyle where Self == Color {
    /// Primary text color on glass surfaces
    public static var tetherOnGlassPrimary: Color { .primary }
    /// Secondary text color on glass surfaces
    public static var tetherOnGlassSecondary: Color { .secondary }
}

// MARK: - Gradient Presets

extension LinearGradient {
    public static let tetherFocusGradient = LinearGradient(
        colors: [.tetherFocused.opacity(0.8), .tetherFocused],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    public static let tetherAccentGradient = LinearGradient(
        colors: [Color.accentColor.opacity(0.8), Color.accentColor],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
