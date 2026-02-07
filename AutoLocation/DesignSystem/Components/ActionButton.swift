import SwiftUI

struct ActionButton: View {
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var isLoading: Bool = false
    var isFullWidth: Bool = true
    var action: () -> Void

    enum Style {
        case primary
        case secondary
        case destructive
        case success
        case warning

        var backgroundColor: Color {
            switch self {
            case .primary: return DS.Colors.active
            case .secondary: return DS.Colors.textPrimary.opacity(0.06)
            case .destructive: return DS.Colors.error
            case .success: return DS.Colors.success
            case .warning: return DS.Colors.warning
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary, .destructive, .success, .warning: return .white
            case .secondary: return DS.Colors.textPrimary
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(style.foregroundColor)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(style.foregroundColor)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, DS.Spacing.xs + 2)
            .padding(.horizontal, DS.Spacing.md)
            .background(style.backgroundColor, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .opacity(isLoading ? 0.7 : 1)
    }
}
