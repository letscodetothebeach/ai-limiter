import SwiftUI

public struct QuotaBarView: View {
    public let quota: QuotaWindow
    public var accentColorOverride: Color? = nil

    public init(quota: QuotaWindow, accentColorOverride: Color? = nil) {
        self.quota = quota
        self.accentColorOverride = accentColorOverride
    }

    private var barGradient: LinearGradient {
        if let override = accentColorOverride {
            return LinearGradient(colors: [override, override.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }

        if quota.utilization >= 85.0 {
            return LinearGradient(
                colors: [Color(red: 0.95, green: 0.35, blue: 0.35), Color(red: 0.85, green: 0.15, blue: 0.15)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if quota.utilization >= 60.0 {
            return LinearGradient(
                colors: [Color(red: 0.95, green: 0.70, blue: 0.20), Color(red: 0.90, green: 0.50, blue: 0.15)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [Color(red: 0.20, green: 0.80, blue: 0.55), Color(red: 0.10, green: 0.65, blue: 0.70)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var statusBadgeColor: Color {
        if quota.utilization >= 85.0 {
            return Color.red.opacity(0.2)
        } else if quota.utilization >= 60.0 {
            return Color.orange.opacity(0.2)
        } else {
            return Color.green.opacity(0.2)
        }
    }

    private var statusTextColor: Color {
        if quota.utilization >= 85.0 {
            return Color.red
        } else if quota.utilization >= 60.0 {
            return Color.orange
        } else {
            return Color.green
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: Name, Reset badge, and Utilization %
            HStack {
                Text(quota.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                if quota.resetsAt != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                        Text(quota.formattedResetTime)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(quota.utilizationPercentageString) used")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(statusTextColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusBadgeColor)
                        .cornerRadius(5)

                    Text("(\(quota.remainingPercentageString) left)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Progress Bar Track & Fill
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 10)

                    // Active fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(barGradient)
                        .frame(width: max(0, min(geo.size.width * CGFloat(quota.utilization / 100.0), geo.size.width)), height: 10)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: quota.utilization)
                }
            }
            .frame(height: 10)
        }
        .padding(.vertical, 2)
    }
}
