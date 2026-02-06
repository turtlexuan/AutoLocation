import SwiftUI

struct JoystickView: View {
    let radius: CGFloat
    var onUpdate: (Double, Double) -> Void  // (bearing in degrees, magnitude 0–1)

    @State private var dragOffset: CGSize = .zero

    private var thumbRadius: CGFloat { radius * 0.25 }

    var body: some View {
        ZStack {
            // Compass labels
            compassLabels

            // Outer ring
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)

            // Cross-hair guides
            Path { path in
                path.move(to: CGPoint(x: radius, y: 4))
                path.addLine(to: CGPoint(x: radius, y: radius * 2 - 4))
                path.move(to: CGPoint(x: 4, y: radius))
                path.addLine(to: CGPoint(x: radius * 2 - 4, y: radius))
            }
            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            .frame(width: radius * 2, height: radius * 2)

            // Direction line from center to thumb
            if dragOffset != .zero {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: dragOffset.width, y: dragOffset.height))
                }
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
            }

            // Thumb
            Circle()
                .fill(Color.accentColor)
                .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                .shadow(color: .accentColor.opacity(0.3), radius: 4)
                .offset(dragOffset)
        }
        .frame(width: radius * 2 + 30, height: radius * 2 + 30)
        .contentShape(Circle().size(width: radius * 2 + 30, height: radius * 2 + 30))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let translation = value.translation
                    let dist = sqrt(translation.width * translation.width +
                                    translation.height * translation.height)
                    let clamped = min(dist, radius)

                    if dist > 0 {
                        let scale = clamped / dist
                        dragOffset = CGSize(
                            width: translation.width * scale,
                            height: translation.height * scale
                        )
                    }

                    // Angle: 0 = north (up), clockwise
                    let angle = atan2(translation.width, -translation.height) * 180.0 / .pi
                    let normalizedAngle = angle < 0 ? angle + 360 : angle
                    let magnitude = clamped / radius

                    onUpdate(normalizedAngle, magnitude)
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = .zero
                    }
                    onUpdate(0, 0)
                }
        )
    }

    private var compassLabels: some View {
        let labelOffset = radius + 12
        return ZStack {
            Text("N")
                .offset(y: -labelOffset)
            Text("S")
                .offset(y: labelOffset)
            Text("E")
                .offset(x: labelOffset)
            Text("W")
                .offset(x: -labelOffset)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
