import Foundation

public enum AccountStatus: Codable, Equatable, Sendable {
    case active
    case refreshing
    case expired
    case rateLimited(resetsAt: Date?)
    case error(String)

    public var title: String {
        switch self {
        case .active: return "Active"
        case .refreshing: return "Refreshing..."
        case .expired: return "Token Expired"
        case .rateLimited: return "Rate Limited (429)"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }

    public var isNeedsAuth: Bool {
        switch self {
        case .error, .expired: return true
        default: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case active, refreshing, expired, rateLimited, error
    }

    private enum RateLimitedKeys: String, CodingKey {
        case resetsAt
    }

    private enum ErrorKeys: String, CodingKey {
        case _0
    }

    public init(from decoder: Decoder) throws {
        // Support decoding from plain string if present
        if let single = try? decoder.singleValueContainer(), let str = try? single.decode(String.self) {
            switch str.lowercased() {
            case "active": self = .active
            case "refreshing": self = .refreshing
            case "expired": self = .expired
            default: self = .active
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.active) {
            self = .active
        } else if container.contains(.refreshing) {
            self = .refreshing
        } else if container.contains(.expired) {
            self = .expired
        } else if container.contains(.rateLimited) {
            let sub = try? container.nestedContainer(keyedBy: RateLimitedKeys.self, forKey: .rateLimited)
            let resetsAt = try? sub?.decodeIfPresent(Date.self, forKey: .resetsAt)
            self = .rateLimited(resetsAt: resetsAt ?? nil)
        } else if container.contains(.error) {
            let sub = try? container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
            let msg = (try? sub?.decode(String.self, forKey: ._0)) ?? "Unknown error"
            self = .error(msg)
        } else {
            self = .active
        }
    }
}

public struct QuotaWindow: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let utilization: Double      // Percentage used: 0 - 100
    public let resetsAt: Date?
    public let total: Double           // Typically 100

    public init(name: String, utilization: Double, resetsAt: Date?, total: Double = 100) {
        self.name = name
        self.utilization = min(max(utilization, 0), 100)
        self.resetsAt = resetsAt
        self.total = total
    }

    public var remaining: Double {
        return max(0, 100 - utilization)
    }

    public var remainingPercentageString: String {
        return String(format: "%.1f%%", remaining)
    }

    public var utilizationPercentageString: String {
        return String(format: "%.1f%%", utilization)
    }

    public var formattedResetTime: String {
        guard let resetsAt = resetsAt else { return "Unknown" }
        let now = Date()
        let diff = resetsAt.timeIntervalSince(now)
        if diff <= 0 {
            return "Resets now"
        }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }
}

public struct UsageData: Codable, Equatable, Sendable {
    public var plan: String
    public var organization: String?
    public var session5h: QuotaWindow?
    public var weekly7d: QuotaWindow?
    public var modelQuotas: [QuotaWindow]
    public var extraUsage: String?
    public var fetchedAt: Date

    public init(
        plan: String = "Claude Code",
        organization: String? = nil,
        session5h: QuotaWindow? = nil,
        weekly7d: QuotaWindow? = nil,
        modelQuotas: [QuotaWindow] = [],
        extraUsage: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.plan = plan
        self.organization = organization
        self.session5h = session5h
        self.weekly7d = weekly7d
        self.modelQuotas = modelQuotas
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }
}

public struct ProxyConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var url: String // e.g. "http://127.0.0.1:7890" or "socks5://127.0.0.1:1080"

    public init(isEnabled: Bool = false, url: String = "http://127.0.0.1:7890") {
        self.isEnabled = isEnabled
        self.url = url
    }
}

public struct Account: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var email: String?
    public var organizationName: String?
    public var accountUUID: String?
    
    // Package & Account Category
    public var plan: String?               // e.g. "Max", "Max (20x)", "Pro", "Ultra", "Team"
    public var accountType: String?        // e.g. "Personal", "Business", "Team"
    public var rateLimitTier: String?      // e.g. "default_claude_max_20x"

    // Tokens
    public var accessToken: String
    public var refreshToken: String?
    public var tokenExpiresAt: Date?
    
    // Proxy settings per account
    public var proxy: ProxyConfig
    
    // Status & Usage
    public var isMock: Bool
    public var status: AccountStatus
    public var usage: UsageData?
    public var lastUpdated: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        organizationName: String? = nil,
        accountUUID: String? = nil,
        plan: String? = nil,
        accountType: String? = nil,
        rateLimitTier: String? = nil,
        accessToken: String = "",
        refreshToken: String? = nil,
        tokenExpiresAt: Date? = nil,
        proxy: ProxyConfig = ProxyConfig(),
        isMock: Bool = false,
        status: AccountStatus = .active,
        usage: UsageData? = nil,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.organizationName = organizationName
        self.accountUUID = accountUUID
        self.plan = plan
        self.accountType = accountType
        self.rateLimitTier = rateLimitTier
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiresAt = tokenExpiresAt
        self.proxy = proxy
        self.isMock = isMock
        self.status = status
        self.usage = usage
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Display Helpers & Inference

public extension Account {
    var isNeedsAuth: Bool {
        status.isNeedsAuth
    }

    /// Inferred or explicit account type: "Personal" or "Business" / "Team"
    var displayAccountType: String {
        if let type = accountType, !type.isEmpty {
            let lower = type.lowercased()
            if lower.contains("personal") { return "Personal" }
            if lower.contains("team") { return "Team" }
            if lower.contains("business") || lower.contains("company") || lower.contains("enterprise") { return "Business" }
            return type.capitalized
        }
        let org = (organizationName ?? name).lowercased()
        if org.contains("'s organization") || org.contains("personal") {
            return "Personal"
        }
        if let email = email, org.contains(email.lowercased()) {
            return "Personal"
        }
        return "Business"
    }

    /// Inferred or explicit package / plan: "Ultra", "Max", "Pro", "Team", "Free"
    var displayPlan: String {
        if let p = plan, !p.isEmpty && p != "Claude Code" {
            return formatPlanString(p)
        }
        if let tier = rateLimitTier, !tier.isEmpty {
            let lower = tier.lowercased()
            if lower.contains("max_20x") || lower.contains("20x") { return "Max (20x)" }
            if lower.contains("max_5x") || lower.contains("5x") { return "Max (5x)" }
            if lower.contains("max") { return "Max" }
            if lower.contains("ultra") { return "Ultra" }
            if lower.contains("pro") || lower.contains("claude_ai") { return "Pro" }
            if lower.contains("team") { return "Team" }
        }
        if let uPlan = usage?.plan, !uPlan.isEmpty && uPlan != "Claude Code" {
            return formatPlanString(uPlan)
        }
        // Inferred fallback based on organizationName or email
        let org = (organizationName ?? "").lowercased()
        if org.contains("enterprise") || org.contains("ultra") {
            return "Ultra"
        }
        if org.contains("team") {
            return "Team"
        }
        return "Pro"
    }

    /// User-friendly display name avoiding clumsy "xxx@gmail.com's Organization"
    var cleanDisplayName: String {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.contains("'s Organization") {
            let prefix = raw.replacingOccurrences(of: "'s Organization", with: "")
            if let atIdx = prefix.firstIndex(of: "@") {
                return String(prefix[..<atIdx])
            }
            return prefix
        }
        if let email = email, raw.lowercased() == "\(email.lowercased())'s organization" {
            if let atIdx = email.firstIndex(of: "@") {
                return String(email[..<atIdx])
            }
            return "Personal"
        }
        return raw.isEmpty ? (email ?? "Account") : raw
    }

    private func formatPlanString(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("20x") { return "Max (20x)" }
        if lower.contains("5x") { return "Max (5x)" }
        if lower.contains("max") { return "Max" }
        if lower.contains("ultra") { return "Ultra" }
        if lower.contains("pro") { return "Pro" }
        if lower.contains("team") { return "Team" }
        return raw
    }
}
