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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(String(format: "%.0f%%", q.utilization))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)

                    if q.resetsAt != nil {
                        Text("• \(q.formattedResetTime)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                // Mini horizontal bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 100, height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(statusColor)
                        .frame(width: max(0, min(100 * CGFloat(q.utilization / 100.0), 100)), height: 6)
                }
            }
            .help("\(title): \(q.utilizationPercentageString) used (\(q.remainingPercentageString) left)\nResets: \(q.formattedResetTime)")
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 100, alignment: .leading)
        }
    }
}
