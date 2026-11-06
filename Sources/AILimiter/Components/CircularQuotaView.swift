import SwiftUI

public struct CircularQuotaView: View {
    public let title: String
    public let utilization: Double
    public let resetTime: String?
    public var size: CGFloat = 80

    public init(title: String, utilization: Double, resetTime: String? = nil, size: CGFloat = 80) {
        self.title = title
        self.utilization = min(max(utilization, 0), 100)
        self.resetTime = resetTime
        self.size = size
    }

    private var ringColor: Color {
        if utilization >= 85 {
            return Color(red: 0.95, green: 0.35, blue: 0.35)
        } else if utilization >= 60 {
            return Color(red: 0.95, green: 0.65, blue: 0.20)
        } else {
            return Color(red: 0.20, green: 0.80, blue: 0.55)
        }
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    .frame(width: size, height: size)

                // Fill Ring
                Circle()
                    .trim(from: 0.0, to: CGFloat(utilization / 100.0))
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: utilization)

                // Center Label
                VStack(spacing: 2) {
                    Text(String(format: "%.0f%%", utilization))
                        .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("USED")
                        .font(.system(size: size * 0.11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if let resetTime = resetTime {
                Text(resetTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }
}
