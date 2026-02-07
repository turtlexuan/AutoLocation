import SwiftUI

// MARK: - Design System Namespace

enum DS {

    // MARK: - Colors

    enum Colors {
        // Backgrounds
        static let backgroundPrimary = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let surfaceElevated = Color(.white).opacity(0.06)
        static let border = Color.primary.opacity(0.08)
        static let borderSubtle = Color.primary.opacity(0.05)

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.35)

        // Semantic
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        static let active = Color.accentColor

        // Feature-specific
        static let route = Color.indigo
        static let movement = Color.cyan
        static let simulation = Color.blue
    }

    // MARK: - Typography

    enum Typography {
        static let sectionTitle = Font.system(.subheadline, design: .default, weight: .semibold)
        static let cardTitle = Font.system(.body, design: .default, weight: .medium)
        static let body = Font.system(.body, design: .default)
        static let bodySmall = Font.system(.callout, design: .default)
        static let label = Font.system(.caption, design: .default)
        static let labelSmall = Font.system(.caption2, design: .default)
        static let mono = Font.system(.caption, design: .monospaced)
        static let stat = Font.system(.caption, design: .monospaced, weight: .medium)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Animation

    enum Animation {
        static let fast: SwiftUI.Animation = .easeInOut(duration: 0.15)
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.25)
        static let slow: SwiftUI.Animation = .easeInOut(duration: 0.4)
        static let spring: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.7)
        static let bouncy: SwiftUI.Animation = .spring(response: 0.4, dampingFraction: 0.6)
    }
}

// MARK: - Shadow View Modifiers

struct ShadowSubtle: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}

struct ShadowMedium: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

struct ShadowElevated: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 4)
    }
}

struct ShadowGlow: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 0)
    }
}

extension View {
    func shadowSubtle() -> some View {
        modifier(ShadowSubtle())
    }

    func shadowMedium() -> some View {
        modifier(ShadowMedium())
    }

    func shadowElevated() -> some View {
        modifier(ShadowElevated())
    }

    func shadowGlow(_ color: Color) -> some View {
        modifier(ShadowGlow(color: color))
    }
}
