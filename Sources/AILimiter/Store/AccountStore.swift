import Foundation
import Combine

@MainActor
public class AccountStore: ObservableObject {
    private let autoRefreshEnabledKey = "AILimiter.autoRefreshEnabled"
    private let autoRefreshIntervalKey = "AILimiter.autoRefreshInterval"

    @Published public var accounts: [Account] = []
    @Published public var isRefreshingAll: Bool = false
    @Published public var autoRefreshEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoRefreshEnabled, forKey: autoRefreshEnabledKey)
            setupAutoRefreshTimer()
        }
    }
    @Published public var autoRefreshIntervalSeconds: TimeInterval {
        didSet {
            UserDefaults.standard.set(autoRefreshIntervalSeconds, forKey: autoRefreshIntervalKey)
            setupAutoRefreshTimer()
        }
    }
    @Published public var selectedAccountId: UUID?
    @Published public var lastGlobalRefresh: Date?

    private var autoRefreshTimer: AnyCancellable?
    private let storageUrl: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AILimiter", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageUrl = appDir.appendingPathComponent("accounts.json")

        // Load saved auto-refresh preferences
        if UserDefaults.standard.object(forKey: autoRefreshEnabledKey) != nil {
            self.autoRefreshEnabled = UserDefaults.standard.bool(forKey: autoRefreshEnabledKey)
        } else {
            self.autoRefreshEnabled = true
        }

        let savedInterval = UserDefaults.standard.double(forKey: autoRefreshIntervalKey)
        self.autoRefreshIntervalSeconds = savedInterval > 0 ? savedInterval : 300

        loadAccounts()
        setupAutoRefreshTimer()
    }

    // MARK: - Persistence

    public func saveAccounts() {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: storageUrl, options: [.atomic])
        } catch {
            print("Failed to save accounts: \(error)")
        }
    }

    public func loadAccounts() {
        guard FileManager.default.fileExists(atPath: storageUrl.path) else {
            self.accounts = []
            return
        }

        do {
            let data = try Data(contentsOf: storageUrl)
            let decoded = try JSONDecoder().decode([Account].self, from: data)
            self.accounts = decoded
        } catch {
            print("Failed to decode accounts: \(error)")
            self.accounts = []
        }
    }

    public func clearAllMockAccounts() {
        accounts.removeAll { $0.isMock }
        saveAccounts()
    }

    public func clearAllAccounts() {
        accounts.removeAll()
        saveAccounts()
    }

    public func seedInitialMockAccounts() {
        let mockPro = Account(
            name: "Personal Claude Pro",
            email: "developer@example.com",
            organizationName: "Personal Pro",
            accountUUID: "acct_uuid_mock_1",
            accessToken: "mock_token_1",
            proxy: ProxyConfig(isEnabled: false, url: "http://127.0.0.1:7890"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .normal),
            lastUpdated: Date()
        )

        let mockTeam = Account(
            name: "Work Team Account (Proxy Enabled)",
            email: "team-lead@company.internal",
            organizationName: "Dev Engineering Team",
            accountUUID: "acct_uuid_mock_2",
            accessToken: "mock_token_2",
            proxy: ProxyConfig(isEnabled: true, url: "http://127.0.0.1:7890"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .heavy),
            lastUpdated: Date().addingTimeInterval(-180)
        )

        let mockNearLimit = Account(
            name: "High Activity Bot",
            email: "ci-runner@cloud.net",
            organizationName: "Automated Workflows",
            accountUUID: "acct_uuid_mock_3",
            accessToken: "mock_token_3",
            proxy: ProxyConfig(isEnabled: false, url: "socks5://127.0.0.1:1080"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .critical),
            lastUpdated: Date().addingTimeInterval(-45)
        )

        self.accounts = [mockPro, mockTeam, mockNearLimit]
        saveAccounts()
    }

    // MARK: - Account Management

    public func addAccount(_ account: Account) {
        accounts.append(account)
        saveAccounts()
    }

    public func moveAccounts(fromOffsets: IndexSet, toOffset: Int) {
        accounts.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveAccounts()
    }

    public func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        if selectedAccountId == id {
            selectedAccountId = nil
        }
        saveAccounts()
    }

    public func updateAccountName(id: UUID, newName: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAccounts()
    }

    public func toggleProxy(for id: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].proxy.isEnabled.toggle()
        saveAccounts()
    }

    public func setProxy(for id: UUID, isEnabled: Bool, url: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].proxy.isEnabled = isEnabled
        accounts[index].proxy.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAccounts()
    }

    public func addMockAccount(scenario: MockScenario = .normal) {
        let count = accounts.filter { $0.isMock }.count + 1
        var emailPrefix = "test_user_\(count)"
        var orgName = "Test Workspace"
        
        switch scenario {
        case .normal:
            emailPrefix = "normal_coder"
            orgName = "Personal Workspace"
        case .heavy:
            emailPrefix = "heavy_builder"
            orgName = "Enterprise Devs"
        case .critical:
            emailPrefix = "limit_tester"
            orgName = "High Throughput Lab"
        case .rateLimited:
            emailPrefix = "cooldown_user"
            orgName = "Rate Limited Tier"
        case .fresh:
            emailPrefix = "new_starter"
            orgName = "Starter Org"
        }

        let newAccount = Account(
            name: "Mock #\(count): \(scenario.rawValue.components(separatedBy: " ").first ?? "User")",
            email: "\(emailPrefix)@claude.ai",
            organizationName: orgName,
            accountUUID: "mock_uuid_\(UUID().uuidString.prefix(8))",
            accessToken: "mock_access_token_\(count)",
            proxy: ProxyConfig(isEnabled: false, url: "http://127.0.0.1:7890"),
            isMock: true,
            status: scenario == .rateLimited ? .rateLimited(resetsAt: Date().addingTimeInterval(180)) : .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: scenario),
            lastUpdated: Date()
        )

        accounts.append(newAccount)
        saveAccounts()
    }

    // MARK: - Refreshing

    public func refreshAccount(id: UUID) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].status = .refreshing

        var account = accounts[index]

        do {
            if account.isMock {
                // Simulate network latency (250ms)
                try? await Task.sleep(nanoseconds: 250_000_000)
                
                // Slightly randomize usage to show live responsiveness
                var currentUsage = account.usage ?? ClaudeUsageService.shared.generateMockUsage(for: account, scenario: .normal)
                if let s5 = currentUsage.session5h {
                    let jitter = Double.random(in: -1.5...3.0)
                    let newUtil = min(max(s5.utilization + jitter, 1.0), 99.0)
                    currentUsage.session5h = QuotaWindow(name: s5.name, utilization: newUtil, resetsAt: s5.resetsAt)
                }
                currentUsage.fetchedAt = Date()
                account.usage = currentUsage
                account.status = .active
                account.lastUpdated = Date()
            } else {
                // If real account, check token refresh if needed
                if let expiresAt = account.tokenExpiresAt, expiresAt < Date().addingTimeInterval(300),
                   let rt = account.refreshToken, !rt.isEmpty {
                    do {
                        let newTokens = try await ClaudeOAuthService.shared.refreshToken(refreshToken: rt, proxy: account.proxy)
                        account.accessToken = newTokens.accessToken
                        if let newRt = newTokens.refreshToken {
                            account.refreshToken = newRt
                        }
                        if let exp = newTokens.expiresIn {
                            account.tokenExpiresAt = Date().addingTimeInterval(Double(exp))
                        }
                    } catch {
                        print("Token refresh warning: \(error)")
                    }
                }

                // Fetch real usage
                let usage = try await ClaudeUsageService.shared.fetchUsage(for: account)
                account.usage = usage
                account.status = .active
                account.lastUpdated = Date()
            }
        } catch {
            let nsErr = error as NSError
            if nsErr.code == 429 {
                account.status = .rateLimited(resetsAt: Date().addingTimeInterval(180))
            } else {
                account.status = .error(error.localizedDescription)
            }
        }

        if let currentIndex = accounts.firstIndex(where: { $0.id == id }) {
            accounts[currentIndex] = account
            saveAccounts()
        }
    }

    public func refreshAllAccounts() async {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true

        let currentIds = accounts.map { $0.id }
        for id in currentIds {
            await self.refreshAccount(id: id)
        }

        lastGlobalRefresh = Date()
        isRefreshingAll = false
    }

    // MARK: - Auto Refresh Timer

    private func setupAutoRefreshTimer() {
        autoRefreshTimer?.cancel()
        guard autoRefreshEnabled, autoRefreshIntervalSeconds > 0 else { return }

        autoRefreshTimer = Timer.publish(every: autoRefreshIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshAllAccounts()
                }
            }
    }
}
