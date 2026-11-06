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
