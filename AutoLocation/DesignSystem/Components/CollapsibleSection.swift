import SwiftUI

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let storageKey: String
    var badge: String? = nil
    var badgeColor: Color = DS.Colors.active
    var defaultExpanded: Bool = true
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(DS.Animation.standard) {
                    isExpanded.toggle()
                    UserDefaults.standard.set(isExpanded, forKey: storageKey)
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.active)
                        .frame(width: 20)

                    Text(title)
                        .font(DS.Typography.sectionTitle)
                        .foregroundStyle(DS.Colors.textPrimary)

                    if let badge {
                        Text(badge)
                            .font(DS.Typography.labelSmall)
                            .fontWeight(.medium)
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, DS.Spacing.xxs + 2)
                            .padding(.vertical, DS.Spacing.xxxs)
                            .background(badgeColor.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(DS.Animation.standard, value: isExpanded)
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    content()
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .strokeBorder(DS.Colors.border, lineWidth: 1)
                )
        )
        .shadowSubtle()
        .onAppear {
            let stored = UserDefaults.standard.object(forKey: storageKey)
            isExpanded = (stored as? Bool) ?? defaultExpanded
        }
    }
}
