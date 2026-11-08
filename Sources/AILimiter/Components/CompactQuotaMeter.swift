import SwiftUI

public struct CompactQuotaMeter: View {
    public let title: String
    public let quota: QuotaWindow?

    public init(title: String, quota: QuotaWindow?) {
        self.title = title
        self.quota = quota
    }

    private var utilization: Double {
        quota?.utilization ?? 0
    }

    private var statusColor: Color {
        if utilization >= 85.0 {
            return Color(red: 0.95, green: 0.35, blue: 0.35)
        } else if utilization >= 60.0 {
            return Color(red: 0.95, green: 0.65, blue: 0.20)
        } else {
            return Color(red: 0.20, green: 0.80, blue: 0.55)
        }
    }

    public var body: some View {
        if let q = quota {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(String(format: "%.0f%%", q.utilization))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)

                    if q.resetsAt != nil {
                        Text("• \(q.formattedResetTime)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                // Mini horizontal bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 110, height: 7)

                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(statusColor)
                        .frame(width: max(0, min(110 * CGFloat(q.utilization / 100.0), 110)), height: 7)
                }
            }
            .help("\(title): \(q.utilizationPercentageString) used (\(q.remainingPercentageString) left)\nResets: \(q.formattedResetTime)")
        } else {
            Text("—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 110, alignment: .leading)
        }
    }
}
