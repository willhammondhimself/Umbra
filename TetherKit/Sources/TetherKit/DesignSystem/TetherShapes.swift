import SwiftUI

// MARK: - Shared Shape Styles

extension RoundedRectangle {
    public static let tetherCard = RoundedRectangle(cornerRadius: 20, style: .continuous)
    public static let tetherButton = RoundedRectangle(cornerRadius: 12, style: .continuous)
    public static let tetherSmall = RoundedRectangle(cornerRadius: 8, style: .continuous)
}

// MARK: - Corner Radius Constants

public enum TetherRadius {
    public static let card: CGFloat = 20
    public static let button: CGFloat = 12
    public static let small: CGFloat = 8
    public static let sidebar: CGFloat = 16
}
