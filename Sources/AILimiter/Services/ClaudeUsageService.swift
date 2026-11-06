import Foundation

public enum MockScenario: String, CaseIterable, Identifiable {
    case normal = "Normal Usage (32% Session, 45% Weekly)"
    case heavy = "Heavy Usage (84% Session, 72% Weekly)"
    case critical = "Near Limit (96% Session - Resets in 22m)"
    case rateLimited = "Rate Limited (429 Cooldown)"
    case fresh = "Fresh / Idle (5% Session, 10% Weekly)"

    public var id: String { rawValue }
}

@MainActor
public final class ClaudeUsageService {
    public static let shared = ClaudeUsageService()

    public static let oauthUsageUrl = "https://api.anthropic.com/api/oauth/usage"
    public static let settingsUrl = "https://api.anthropic.com/v1/settings"
    public static let orgUsageUrlPattern = "https://api.anthropic.com/v1/organizations/{org_id}/usage"
    public static let apiVersion = "2023-06-01"

    // Cooldown tracker for 429 rate limits (per access token or account)
    private var cooldowns: [String: Date] = [:]

    public init() {}

    // MARK: - Date Parser Helper

    public static func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Usage Fetcher

    public func fetchUsage(for account: Account) async throws -> UsageData {
        if account.isMock {
            return generateMockUsage(for: account)
        }

        // Check if under 429 cooldown
        if let cooldownUntil = cooldowns[account.accessToken], Date() < cooldownUntil {
            let remainingSec = Int(cooldownUntil.timeIntervalSince(Date()))
            throw NSError(domain: "ClaudeUsage", code: 429, userInfo: [
                NSLocalizedDescriptionKey: "Rate limit cooldown active (\(remainingSec)s remaining). Try again shortly."
            ])
        }

        let session = ProxySessionManager.shared.session(for: account.proxy)

        guard let url = URL(string: Self.oauthUsageUrl) else {
            throw NSError(domain: "ClaudeUsage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid usage endpoint URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("claude-code/0.2.29", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ClaudeUsage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response from Anthropic API"])
        }

        // Handle 429 Too Many Requests
        if httpResponse.statusCode == 429 {
            let cooldown = Date().addingTimeInterval(180) // 3 minutes cooldown like llm-hub
            cooldowns[account.accessToken] = cooldown
            throw NSError(domain: "ClaudeUsage", code: 429, userInfo: [
                NSLocalizedDescriptionKey: "Rate limited by Anthropic (429). Cooldown for 3 minutes."
            ])
        }

        if httpResponse.statusCode == 200 {
            return try parseOAuthUsageResponse(data: data)
        }

        // Fallback: try legacy settings / org endpoint if status is 403 / 404
        return try await fetchLegacyOrgUsage(account: account, session: session)
    }

    // MARK: - Parse /api/oauth/usage JSON

    public func parseOAuthUsageResponse(data: Data) throws -> UsageData {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ClaudeUsage", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse usage response JSON"])
        }

        var session5h: QuotaWindow? = nil
        var weekly7d: QuotaWindow? = nil
        var modelQuotas: [QuotaWindow] = []

        // Parse five_hour (session)
        if let fiveHour = json["five_hour"] as? [String: Any],
           let utilization = extractUtilization(from: fiveHour) {
            let resetDate = Self.parseISO8601(fiveHour["resets_at"] as? String)
            session5h = QuotaWindow(name: "Session (5h)", utilization: utilization, resetsAt: resetDate)
        }

        // Parse seven_day (weekly)
        if let sevenDay = json["seven_day"] as? [String: Any],
           let utilization = extractUtilization(from: sevenDay) {
            let resetDate = Self.parseISO8601(sevenDay["resets_at"] as? String)
            weekly7d = QuotaWindow(name: "Weekly (7d)", utilization: utilization, resetsAt: resetDate)
        }

        // Parse model-specific seven_day_<model> keys (e.g. seven_day_sonnet, seven_day_opus)
        for (key, val) in json {
            if key.hasPrefix("seven_day_") && key != "seven_day",
               let modelDict = val as? [String: Any],
               let utilization = extractUtilization(from: modelDict) {
                let modelRaw = String(key.dropFirst("seven_day_".count))
                let displayName = formatModelName(modelRaw)
                let resetDate = Self.parseISO8601(modelDict["resets_at"] as? String)
                modelQuotas.append(QuotaWindow(name: "\(displayName) (7d)", utilization: utilization, resetsAt: resetDate))
            }
        }

        // Parse limits array (e.g. Fable weekly scoped)
        if let limits = json["limits"] as? [[String: Any]] {
            for limit in limits {
                guard (limit["kind"] as? String) == "weekly_scoped",
                      let percent = limit["percent"] as? Double else { continue }
                
                let scope = limit["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let modelName = model?["display_name"] as? String ?? "Custom Model"
                let resetDate = Self.parseISO8601(limit["resets_at"] as? String)

                modelQuotas.append(QuotaWindow(name: "\(modelName) (Weekly)", utilization: percent, resetsAt: resetDate))
            }
        }

        var extraUsageString: String? = nil
        if let extraUsage = json["extra_usage"] as? [String: Any] {
            if let spend = extraUsage["spend"] as? Double {
                extraUsageString = String(format: "$%.2f spend", spend)
            }
        }

        return UsageData(
            plan: "Claude Code",
            organization: nil,
            session5h: session5h,
            weekly7d: weekly7d,
            modelQuotas: modelQuotas,
            extraUsage: extraUsageString,
            fetchedAt: Date()
        )
    }

    private func extractUtilization(from dict: [String: Any]) -> Double? {
        if let u = dict["utilization"] as? Double {
            return u
        }
        if let uInt = dict["utilization"] as? Int {
            return Double(uInt)
        }
        if let p = dict["percent"] as? Double {
            return p
        }
        if let pInt = dict["percent"] as? Int {
            return Double(pInt)
        }
        return nil
    }

    private func formatModelName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "sonnet": return "Claude Sonnet"
        case "opus": return "Claude Opus"
        case "haiku": return "Claude Haiku"
        case "fable": return "Claude Fable"
        default: return raw.capitalized
        }
    }

    // MARK: - Legacy Fallback (settings / organizations)

    private func fetchLegacyOrgUsage(account: Account, session: URLSession) async throws -> UsageData {
        guard let settingsUrl = URL(string: Self.settingsUrl) else {
            throw NSError(domain: "ClaudeUsage", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid settings URL"])
        }

        var request = URLRequest(url: settingsUrl)
        request.httpMethod = "GET"
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ClaudeUsage", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not fetch usage from OAuth or organization endpoints."])
        }

        let plan = settings["plan"] as? String ?? "Anthropic Plan"
        let orgName = settings["organization_name"] as? String

        return UsageData(
            plan: plan,
            organization: orgName,
            session5h: nil,
            weekly7d: nil,
            modelQuotas: [],
            extraUsage: nil,
            fetchedAt: Date()
        )
    }

    // MARK: - Mock Generator

    public func generateMockUsage(for account: Account, scenario: MockScenario = .normal) -> UsageData {
        let now = Date()

        switch scenario {
        case .normal:
            return UsageData(
                plan: "Claude Pro",
                organization: "Personal Pro",
                session5h: QuotaWindow(name: "Session (5h)", utilization: 32.5, resetsAt: now.addingTimeInterval(3600 * 2.8)),
                weekly7d: QuotaWindow(name: "Weekly (7d)", utilization: 48.0, resetsAt: now.addingTimeInterval(3600 * 24 * 4.2)),
                modelQuotas: [
                    QuotaWindow(name: "Claude Sonnet (7d)", utilization: 41.0, resetsAt: now.addingTimeInterval(3600 * 24 * 4.2)),
                    QuotaWindow(name: "Claude Opus (7d)", utilization: 18.0, resetsAt: now.addingTimeInterval(3600 * 24 * 4.2))
                ],
                extraUsage: nil,
                fetchedAt: now
            )

        case .heavy:
            return UsageData(
                plan: "Claude Team",
                organization: "Acme Corp Devs",
                session5h: QuotaWindow(name: "Session (5h)", utilization: 84.5, resetsAt: now.addingTimeInterval(3600 * 1.1)),
                weekly7d: QuotaWindow(name: "Weekly (7d)", utilization: 76.0, resetsAt: now.addingTimeInterval(3600 * 24 * 2.0)),
                modelQuotas: [
                    QuotaWindow(name: "Claude Sonnet (7d)", utilization: 82.0, resetsAt: now.addingTimeInterval(3600 * 24 * 2.0)),
                    QuotaWindow(name: "Claude Opus (7d)", utilization: 68.0, resetsAt: now.addingTimeInterval(3600 * 24 * 2.0))
                ],
                extraUsage: "$45.20 extra spend",
                fetchedAt: now
            )

        case .critical:
            return UsageData(
                plan: "Claude Pro",
                organization: "Deep Coding Work",
                session5h: QuotaWindow(name: "Session (5h)", utilization: 96.8, resetsAt: now.addingTimeInterval(60 * 22)),
                weekly7d: QuotaWindow(name: "Weekly (7d)", utilization: 89.2, resetsAt: now.addingTimeInterval(3600 * 18)),
                modelQuotas: [
                    QuotaWindow(name: "Claude Sonnet (7d)", utilization: 95.0, resetsAt: now.addingTimeInterval(3600 * 18)),
                    QuotaWindow(name: "Claude Opus (7d)", utilization: 88.0, resetsAt: now.addingTimeInterval(3600 * 18))
                ],
                extraUsage: nil,
                fetchedAt: now
            )

        case .rateLimited:
            return UsageData(
                plan: "Claude Pro",
                organization: "Throttled Session",
                session5h: QuotaWindow(name: "Session (5h)", utilization: 100.0, resetsAt: now.addingTimeInterval(180)),
                weekly7d: QuotaWindow(name: "Weekly (7d)", utilization: 75.0, resetsAt: now.addingTimeInterval(3600 * 24 * 3)),
                modelQuotas: [],
                extraUsage: nil,
                fetchedAt: now
            )

        case .fresh:
            return UsageData(
                plan: "Claude Pro",
                organization: "New Billing Cycle",
                session5h: QuotaWindow(name: "Session (5h)", utilization: 6.2, resetsAt: now.addingTimeInterval(3600 * 4.9)),
                weekly7d: QuotaWindow(name: "Weekly (7d)", utilization: 12.0, resetsAt: now.addingTimeInterval(3600 * 24 * 6.5)),
                modelQuotas: [
                    QuotaWindow(name: "Claude Sonnet (7d)", utilization: 5.0, resetsAt: now.addingTimeInterval(3600 * 24 * 6.5))
                ],
                extraUsage: nil,
                fetchedAt: now
            )
        }
    }
}
