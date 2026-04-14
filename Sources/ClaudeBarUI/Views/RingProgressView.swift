import SwiftUI

public struct RingProgressView: View {
    public let progress: Double // 0.0 to 1.0
    public let color: Color
    public let size: CGFloat

    public init(progress: Double, color: Color, size: CGFloat = 16) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.25), lineWidth: size * 0.15)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.15, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

#Preview("Ring Progress") {
    HStack(spacing: 20) {
        RingProgressView(progress: 0.25, color: UsageColor.green.swiftUIColor, size: 32)
        RingProgressView(progress: 0.55, color: UsageColor.yellow.swiftUIColor, size: 32)
        RingProgressView(progress: 0.80, color: UsageColor.orange.swiftUIColor, size: 32)
        RingProgressView(progress: 0.95, color: UsageColor.red.swiftUIColor, size: 32)
    }
    .padding()
}
