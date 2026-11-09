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
    @Published public var accountToReauth: Account? = nil

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
            var decoded = try JSONDecoder().decode([Account].self, from: data)
            var needsSave = false
            for i in 0..<decoded.count {
                if decoded[i].plan == nil {
                    decoded[i].plan = decoded[i].displayPlan
                    needsSave = true
                }
                if decoded[i].accountType == nil {
                    decoded[i].accountType = decoded[i].displayAccountType
                    needsSave = true
                }
            }
            self.accounts = decoded
            if needsSave {
                saveAccounts()
            }
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
            plan: "Pro",
            accountType: "Personal",
            rateLimitTier: "default_claude_ai",
            note: "Personal CLI & Experiments",
            accessToken: "mock_token_1",
            proxy: ProxyConfig(isEnabled: false, url: "http://127.0.0.1:7890"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .normal),
            lastUpdated: Date()
        )

        let mockTeam = Account(
            name: "Dev Engineering Team",
            email: "team-lead@company.internal",
            organizationName: "Dev Engineering Team",
            accountUUID: "acct_uuid_mock_2",
            plan: "Team",
            accountType: "Business",
            rateLimitTier: "team_tier_1",
            note: "Backend Core API Service",
            accessToken: "mock_token_2",
            proxy: ProxyConfig(isEnabled: true, url: "http://127.0.0.1:7890"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .heavy),
            lastUpdated: Date().addingTimeInterval(-180)
        )

        let mockMax = Account(
            name: "Automated Workflows",
            email: "ci-runner@cloud.net",
            organizationName: "Automated Workflows",
            accountUUID: "acct_uuid_mock_3",
            plan: "Max (20x)",
            accountType: "Business",
            rateLimitTier: "default_claude_max_20x",
            note: "CI/CD Code Review Bot",
            accessToken: "mock_token_3",
            proxy: ProxyConfig(isEnabled: false, url: "socks5://127.0.0.1:1080"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .critical),
            lastUpdated: Date().addingTimeInterval(-45)
        )

        let mockUltra = Account(
            name: "DeepMind Research Lab",
            email: "researcher@lab.org",
            organizationName: "DeepMind Research Lab",
            accountUUID: "acct_uuid_mock_4",
            plan: "Ultra",
            accountType: "Business",
            rateLimitTier: "ultra_high_tier",
            note: "LLM Fine-tuning Pipeline",
            accessToken: "mock_token_4",
            proxy: ProxyConfig(isEnabled: false, url: "http://127.0.0.1:7890"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .fresh),
            lastUpdated: Date().addingTimeInterval(-10)
        )

        let mockPersonalMax = Account(
            name: "founder@indie.dev's Organization",
            email: "founder@indie.dev",
            organizationName: "founder@indie.dev's Organization",
            accountUUID: "acct_uuid_mock_5",
            plan: "Max (5x)",
            accountType: "Personal",
            rateLimitTier: "default_claude_max_5x",
            note: "Client Mobile App (iOS)",
            accessToken: "mock_token_5",
            proxy: ProxyConfig(isEnabled: true, url: "socks5://127.0.0.1:1080"),
            isMock: true,
            status: .active,
            usage: ClaudeUsageService.shared.generateMockUsage(for: Account(name: "temp"), scenario: .normal),
            lastUpdated: Date().addingTimeInterval(-20)
        )

        self.accounts = [mockPro, mockTeam, mockMax, mockUltra, mockPersonalMax]
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

    public func updateAccountNote(id: UUID, note: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].note = trimmed.isEmpty ? nil : trimmed
        saveAccounts()
    }

    public func updateAccountTokens(
        id: UUID,
        accessToken: String,
        refreshToken: String?,
        tokenExpiresAt: Date?,
        bootstrap: BootstrapAccount? = nil
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].accessToken = accessToken
        if let rt = refreshToken {
            accounts[index].refreshToken = rt
        }
        accounts[index].tokenExpiresAt = tokenExpiresAt
        if let bs = bootstrap {
            accounts[index].plan = bs.parsedPlan
            accounts[index].accountType = bs.parsedAccountType
            if let org = bs.organizationName, !org.isEmpty {
                accounts[index].organizationName = org
            }
            if let email = bs.accountEmail, !email.isEmpty {
                accounts[index].email = email
            }
            if let tier = bs.organizationRateLimitTier ?? bs.userRateLimitTier {
                accounts[index].rateLimitTier = tier
            }
        }
        accounts[index].isMock = false
        accounts[index].status = .active
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
        var mockPlan = "Pro"
        var mockType = "Personal"
        var mockTier = "default_claude_ai"

        switch scenario {
        case .normal:
            emailPrefix = "personal_dev"
            orgName = "Personal Workspace"
            mockPlan = "Pro"
            mockType = "Personal"
            mockTier = "default_claude_ai"
        case .heavy:
            emailPrefix = "heavy_builder"
            orgName = "Enterprise Devs"
            mockPlan = "Max (20x)"
            mockType = "Business"
            mockTier = "default_claude_max_20x"
        case .critical:
            emailPrefix = "limit_tester"
            orgName = "High Throughput Lab"
            mockPlan = "Max (5x)"
            mockType = "Personal"
            mockTier = "default_claude_max_5x"
        case .rateLimited:
            emailPrefix = "cooldown_user"
            orgName = "Rate Limited Org"
            mockPlan = "Pro"
            mockType = "Personal"
            mockTier = "default_claude_ai"
        case .fresh:
            emailPrefix = "ai_research"
            orgName = "Frontier Research Group"
            mockPlan = "Ultra"
            mockType = "Business"
            mockTier = "ultra_tier"
        }

        let newAccount = Account(
            name: "Mock #\(count): \(scenario.rawValue.components(separatedBy: " ").first ?? "User")",
            email: "\(emailPrefix)@claude.ai",
            organizationName: orgName,
            accountUUID: "mock_uuid_\(UUID().uuidString.prefix(8))",
            plan: mockPlan,
            accountType: mockType,
            rateLimitTier: mockTier,
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

                // If plan or type is missing, try fetching bootstrap
                if account.plan == nil || account.accountType == nil {
                    if let bs = try? await ClaudeOAuthService.shared.fetchBootstrap(accessToken: account.accessToken, proxy: account.proxy) {
                        account.plan = bs.parsedPlan
                        account.accountType = bs.parsedAccountType
                        account.rateLimitTier = bs.organizationRateLimitTier ?? bs.userRateLimitTier
                    } else {
                        account.plan = account.displayPlan
                        account.accountType = account.displayAccountType
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
