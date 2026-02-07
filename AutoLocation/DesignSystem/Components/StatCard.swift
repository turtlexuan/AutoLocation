import SwiftUI

struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: DS.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(DS.Colors.textTertiary)

            Text(value)
                .font(DS.Typography.stat)
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(DS.Typography.labelSmall)
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
        .padding(.horizontal, DS.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(DS.Colors.textPrimary.opacity(0.04))
        )
    }
}
