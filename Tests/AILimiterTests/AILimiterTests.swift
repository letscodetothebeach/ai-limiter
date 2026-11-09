import Testing
import Foundation
@testable import AILimiter

@MainActor
struct AILimiterTests {

    @Test func testPKCEGeneration() throws {
        let pkce = ClaudeOAuthService.generatePKCE()
        #expect(!pkce.verifier.isEmpty)
        #expect(pkce.verifier.count >= 43)
        #expect(!pkce.challenge.isEmpty)
        #expect(!pkce.state.isEmpty)

        // Ensure base64url has no padding or invalid chars
        #expect(!pkce.verifier.contains("="))
        #expect(!pkce.verifier.contains("+"))
        #expect(!pkce.verifier.contains("/"))
        #expect(!pkce.challenge.contains("="))
    }

    @Test func testBuildAuthorizeUrl() throws {
        let pkce = PKCEPair(verifier: "test_verifier", challenge: "test_challenge", state: "test_state")
        let redirectUri = "http://localhost:54321/callback"
        let url = ClaudeOAuthService.buildAuthorizeUrl(redirectUri: redirectUri, pkce: pkce)

        #expect(url != nil)
        let urlString = url!.absoluteString
        #expect(urlString.contains("claude.ai/oauth/authorize"))
        #expect(urlString.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
        #expect(urlString.contains("response_type=code"))
        #expect(urlString.contains("code=true"))
        #expect(urlString.contains("code_challenge=test_challenge"))
        #expect(urlString.contains("code_challenge_method=S256"))
        #expect(urlString.contains("state=test_state"))
        #expect(urlString.contains("scope=org:create_api_key%20user:profile%20user:inference"))
    }

    @Test func testProxySessionManagerHTTP() throws {
        let manager = ProxySessionManager.shared
        let dict = manager.buildProxyDictionary(from: "http://127.0.0.1:7890")

        #expect(dict != nil)
        #expect(dict?[kCFNetworkProxiesHTTPEnable as String] as? Int == 1)
        #expect(dict?[kCFNetworkProxiesHTTPProxy as String] as? String == "127.0.0.1")
        #expect(dict?[kCFNetworkProxiesHTTPPort as String] as? Int == 7890)
        #expect(dict?[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1)
        #expect(dict?[kCFNetworkProxiesHTTPSProxy as String] as? String == "127.0.0.1")
        #expect(dict?[kCFNetworkProxiesHTTPSPort as String] as? Int == 7890)
    }

    @Test func testProxySessionManagerSOCKS5() throws {
        let manager = ProxySessionManager.shared
        let dict = manager.buildProxyDictionary(from: "socks5://proxy.example.com:1080")

        #expect(dict != nil)
        #expect(dict?[kCFStreamPropertySOCKSProxy as String] as? Int == 1)
        #expect(dict?[kCFStreamPropertySOCKSProxyHost as String] as? String == "proxy.example.com")
        #expect(dict?[kCFStreamPropertySOCKSProxyPort as String] as? Int == 1080)
    }

    @Test func testParseOAuthUsageResponse() async throws {
        let sampleJson = """
        {
            "five_hour": {
                "utilization": 37.5,
                "resets_at": "2026-11-06T21:00:00Z"
            },
            "seven_day": {
                "utilization": 62.0,
                "resets_at": "2026-11-12T00:00:00Z"
            },
            "seven_day_sonnet": {
                "utilization": 45.0,
                "resets_at": "2026-11-12T00:00:00Z"
            },
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 80.0,
                    "resets_at": "2026-11-12T00:00:00Z",
                    "scope": {
                        "model": {
                            "display_name": "Fable"
                        }
                    }
                }
            ],
            "extra_usage": {
                "spend": 12.50
            }
        }
        """

        let data = sampleJson.data(using: .utf8)!
        let service = ClaudeUsageService.shared
        let usage = try service.parseOAuthUsageResponse(data: data)

        #expect(usage.session5h != nil)
        #expect(usage.session5h?.utilization == 37.5)
        #expect(usage.session5h?.remaining == 62.5)

        #expect(usage.weekly7d != nil)
        #expect(usage.weekly7d?.utilization == 62.0)
        #expect(usage.weekly7d?.remaining == 38.0)

        // Check model quotas
        #expect(usage.modelQuotas.count == 2)
        let sonnetQuota = usage.modelQuotas.first { $0.name.contains("Sonnet") }
        #expect(sonnetQuota?.utilization == 45.0)

        let fableQuota = usage.modelQuotas.first { $0.name.contains("Fable") }
        #expect(fableQuota?.utilization == 80.0)

        #expect(usage.extraUsage == "$12.50 spend")
    }

    @Test @MainActor func testAccountStoreCRUD() async throws {
        let store = AccountStore()
        let initialCount = store.accounts.count

        let testAccount = Account(
            name: "Unit Test Account",
            email: "unittest@anthropic.mock",
            organizationName: "Test Org",
            accessToken: "test_token",
            proxy: ProxyConfig(isEnabled: false, url: "http://127.0.0.1:7890"),
            isMock: true,
            status: .active,
            usage: nil,
            lastUpdated: nil
        )

        // Add
        store.addAccount(testAccount)
        #expect(store.accounts.count == initialCount + 1)
        #expect(store.accounts.contains(where: { $0.id == testAccount.id }))

        // Toggle proxy
        store.toggleProxy(for: testAccount.id)
        let updatedAccount = store.accounts.first(where: { $0.id == testAccount.id })
        #expect(updatedAccount?.proxy.isEnabled == true)

        // Update proxy url
        store.setProxy(for: testAccount.id, isEnabled: true, url: "socks5://127.0.0.1:1080")
        let proxyUpdated = store.accounts.first(where: { $0.id == testAccount.id })
        #expect(proxyUpdated?.proxy.url == "socks5://127.0.0.1:1080")

        // Rename
        store.updateAccountName(id: testAccount.id, newName: "Renamed Unit Test")
        let renamedAccount = store.accounts.first(where: { $0.id == testAccount.id })
        #expect(renamedAccount?.name == "Renamed Unit Test")

        // Update Project Note
        store.updateAccountNote(id: testAccount.id, note: "Project Mobile iOS")
        let notedAccount = store.accounts.first(where: { $0.id == testAccount.id })
        #expect(notedAccount?.note == "Project Mobile iOS")

        // Clear Note with empty whitespace
        store.updateAccountNote(id: testAccount.id, note: "   ")
        let clearedNoteAccount = store.accounts.first(where: { $0.id == testAccount.id })
        #expect(clearedNoteAccount?.note == nil)

        // Refresh mock account
        await store.refreshAccount(id: testAccount.id)
        let refreshed = store.accounts.first(where: { $0.id == testAccount.id })
        #expect(refreshed?.usage != nil)
        #expect(refreshed?.lastUpdated != nil)

        // Remove
        store.removeAccount(id: testAccount.id)
        #expect(!store.accounts.contains(where: { $0.id == testAccount.id }))
    }

    @Test @MainActor func testReorderAndStatePersistence() throws {
        let store = AccountStore()
        let a1 = Account(name: "Account 1")
        let a2 = Account(name: "Account 2")
        let a3 = Account(name: "Account 3")

        store.addAccount(a1)
        store.addAccount(a2)
        store.addAccount(a3)

        // Move a1 to bottom
        if let idx1 = store.accounts.firstIndex(where: { $0.id == a1.id }) {
            store.moveAccounts(fromOffsets: IndexSet(integer: idx1), toOffset: store.accounts.count)
            #expect(store.accounts.last?.id == a1.id)
        }

        // Test auto-refresh persistence
        store.autoRefreshEnabled = false
        store.autoRefreshIntervalSeconds = 900

        #expect(UserDefaults.standard.bool(forKey: "AILimiter.autoRefreshEnabled") == false)
        #expect(UserDefaults.standard.double(forKey: "AILimiter.autoRefreshInterval") == 900)

        // Reset
        store.autoRefreshEnabled = true
        store.autoRefreshIntervalSeconds = 300

        store.removeAccount(id: a1.id)
        store.removeAccount(id: a2.id)
        store.removeAccount(id: a3.id)
    }

    @Test func testMockScenarios() throws {
        let service = ClaudeUsageService.shared
        let dummyAccount = Account(name: "dummy")

        let normal = service.generateMockUsage(for: dummyAccount, scenario: .normal)
        #expect(normal.session5h?.utilization == 32.5)
        #expect(normal.weekly7d?.utilization == 48.0)

        let critical = service.generateMockUsage(for: dummyAccount, scenario: .critical)
        #expect(critical.session5h?.utilization == 96.8)
        #expect(critical.session5h?.remainingPercentageString == "3.2%")
    }

    @Test func testAccountPlanAndTypeInference() throws {
        // Personal with email organization
        let personalAcct = Account(
            name: "developer.one@gmail.com's Organization",
            email: "developer.one@gmail.com",
            organizationName: "developer.one@gmail.com's Organization",
            plan: "Max (20x)",
            accountType: "Personal"
        )
        #expect(personalAcct.cleanDisplayName == "developer.one")
        #expect(personalAcct.displayAccountType == "Personal")
        #expect(personalAcct.displayPlan == "Max (20x)")

        // Business with custom company name
        let companyAcct = Account(
            name: "Acme Cloud Studio",
            email: "lead@acmestudio.net",
            organizationName: "Acme Cloud Studio",
            rateLimitTier: "default_claude_max_5x"
        )
        #expect(companyAcct.cleanDisplayName == "Acme Cloud Studio")
        #expect(companyAcct.displayAccountType == "Business")
        #expect(companyAcct.displayPlan == "Max (5x)")

        // Ultra tier
        let ultraAcct = Account(
            name: "Frontier Lab",
            organizationName: "AI Research Lab",
            plan: "Ultra",
            accountType: "Business"
        )
        #expect(ultraAcct.cleanDisplayName == "Frontier Lab")
        #expect(ultraAcct.displayAccountType == "Business")
        #expect(ultraAcct.displayPlan == "Ultra")
    }

    @Test func testBootstrapAccountPlanParsing() throws {
        let max20x = BootstrapAccount(
            accountUuid: "uuid-1",
            accountEmail: "dev@example.com",
            organizationUuid: "org-1",
            organizationName: "dev@example.com's Organization",
            organizationType: "claude_max",
            organizationRateLimitTier: "default_claude_max_20x",
            userRateLimitTier: nil,
            seatTier: nil
        )
        #expect(max20x.parsedPlan == "Max (20x)")
        #expect(max20x.parsedAccountType == "Personal")

        let team5x = BootstrapAccount(
            accountUuid: "uuid-2",
            accountEmail: "leader@corp.io",
            organizationUuid: "org-2",
            organizationName: "Tech Hub Corp",
            organizationType: "claude_team",
            organizationRateLimitTier: "default_raven",
            userRateLimitTier: "default_claude_max_5x",
            seatTier: "team_tier_1"
        )
        #expect(team5x.parsedPlan == "Max (5x)")
        #expect(team5x.parsedAccountType == "Business")

        let pro = BootstrapAccount(
            accountUuid: "uuid-3",
            accountEmail: "solo@gmail.com",
            organizationUuid: "org-3",
            organizationName: "solo@gmail.com's Organization",
            organizationType: "claude_pro",
            organizationRateLimitTier: "default_claude_ai",
            userRateLimitTier: nil,
            seatTier: nil
        )
        #expect(pro.parsedPlan == "Pro")
        #expect(pro.parsedAccountType == "Personal")
    }

    @Test func testReauthAndErrorStatusHelpers() throws {
        let activeStatus = AccountStatus.active
        #expect(!activeStatus.isError)
        #expect(!activeStatus.isNeedsAuth)
        #expect(activeStatus.errorMessage == nil)

        let errorStatus = AccountStatus.error("Connection failed")
        #expect(errorStatus.isError)
        #expect(errorStatus.isNeedsAuth)
        #expect(errorStatus.errorMessage == "Connection failed")

        let expiredStatus = AccountStatus.expired
        #expect(!expiredStatus.isError)
        #expect(expiredStatus.isNeedsAuth)

        let account = Account(name: "Acme Engineer", status: errorStatus)
        #expect(account.isNeedsAuth)
    }

    @Test func testUpdateAccountTokens() throws {
        let store = AccountStore()
        let id = UUID()
        let initialAcct = Account(
            id: id,
            name: "Team Tester",
            accessToken: "old_token",
            refreshToken: "old_refresh",
            status: .error("Token revoked")
        )
        store.accounts = [initialAcct]

        #expect(store.accounts[0].isNeedsAuth)
        #expect(store.accounts[0].accessToken == "old_token")

        let mockBootstrap = BootstrapAccount(
            accountUuid: "uuid-99",
            accountEmail: "team@example.com",
            organizationUuid: "org-99",
            organizationName: "Team Workspace",
            organizationType: "claude_team",
            organizationRateLimitTier: "default_claude_max_20x",
            userRateLimitTier: nil,
            seatTier: nil
        )

        let newExpires = Date().addingTimeInterval(3600)
        store.updateAccountTokens(
            id: id,
            accessToken: "new_token_xyz",
            refreshToken: "new_refresh_abc",
            tokenExpiresAt: newExpires,
            bootstrap: mockBootstrap
        )

        #expect(store.accounts[0].accessToken == "new_token_xyz")
        #expect(store.accounts[0].refreshToken == "new_refresh_abc")
        #expect(store.accounts[0].status == .active)
        #expect(!store.accounts[0].isNeedsAuth)
        #expect(store.accounts[0].plan == "Max (20x)")
        #expect(store.accounts[0].accountType == "Business")
    }

    @Test @MainActor func testAccountNoteAndSearchFiltering() throws {
        // Test Backward Compatibility: JSON without note decodes with note = nil
        let legacyJson = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Account",
            "accessToken": "legacy_tok",
            "proxy": { "isEnabled": false, "url": "http://127.0.0.1:7890" },
            "isMock": true,
            "status": "active"
        }
        """
        let decoded = try JSONDecoder().decode(Account.self, from: legacyJson.data(using: .utf8)!)
        #expect(decoded.name == "Legacy Account")
        #expect(decoded.note == nil)

        // Test Encoding & Decoding with note
        let newAcct = Account(name: "Noted Account", note: "Project Phoenix")
        #expect(newAcct.note == "Project Phoenix")

        let encodedData = try JSONEncoder().encode(newAcct)
        let roundTripped = try JSONDecoder().decode(Account.self, from: encodedData)
        #expect(roundTripped.note == "Project Phoenix")

        // Test Filtering by Project Note
        let store = AccountStore()
        let acct1 = Account(name: "Account A", note: "Phoenix Backend")
        let acct2 = Account(name: "Account B", note: "Mobile Flutter App")
        let acct3 = Account(name: "Account C")

        store.accounts = [acct1, acct2, acct3]

        func search(_ query: String) -> [Account] {
            let q = query.lowercased()
            return store.accounts.filter {
                $0.name.lowercased().contains(q) ||
                ($0.email?.lowercased().contains(q) ?? false) ||
                ($0.organizationName?.lowercased().contains(q) ?? false) ||
                ($0.note?.lowercased().contains(q) ?? false)
            }
        }

        #expect(search("phoenix").count == 1)
        #expect(search("phoenix").first?.name == "Account A")
        #expect(search("flutter").count == 1)
        #expect(search("flutter").first?.name == "Account B")
        #expect(search("Account").count == 3)
        #expect(search("nonexistent").isEmpty)
    }
}
