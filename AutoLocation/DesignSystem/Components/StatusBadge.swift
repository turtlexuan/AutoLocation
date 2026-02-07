import SwiftUI

struct StatusBadge: View {
    let label: String
    let color: Color
    var size: Size = .regular

    enum Size {
        case small
        case regular

        var dotSize: CGFloat {
            switch self {
            case .small: return 6
            case .regular: return 8
            }
        }

        var font: Font {
            switch self {
            case .small: return DS.Typography.labelSmall
            case .regular: return DS.Typography.label
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .small:
                return EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 8)
            case .regular:
                return EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 10)
            }
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xxs + 1) {
            Circle()
                .fill(color)
                .frame(width: size.dotSize, height: size.dotSize)

            Text(label)
                .font(size.font)
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .padding(size.padding)
        .background(color.opacity(0.1), in: Capsule())
    }
}
