import SwiftUI

// MARK: - Semantic Color Tokens

extension Color {
    public static let umbraFocused = Color.green
    public static let umbraDistracted = Color.red
    public static let umbraPaused = Color.orange
    public static let umbraIdle = Color.secondary
    public static let umbraStreak = Color.orange
    public static let umbraPositive = Color.green
    public static let umbraWarning = Color.yellow
    public static let umbraNeutral = Color.blue
}

// MARK: - Session Status Color

extension Color {
    public static func forSessionStatus(_ isDistracted: Bool, isPaused: Bool) -> Color {
        if isPaused { return .umbraPaused }
        if isDistracted { return .umbraDistracted }
        return .umbraFocused
    }
}
