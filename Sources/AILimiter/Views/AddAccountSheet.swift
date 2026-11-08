import SwiftUI
import AppKit

public struct AddAccountSheet: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var isStartingOAuth: Bool = false
    @State private var oauthStatusMessage: String = "Click 'Authorize in Browser' to begin."
    @State private var currentPort: UInt16? = nil
    @State private var currentRedirectUri: String? = nil
    @State private var currentPKCE: PKCEPair? = nil
    @State private var oauthAuthUrl: URL? = nil
    @State private var manualAuthCode: String = ""
    @State private var oauthErrorMessage: String? = nil
    @State private var isExchangingCode: Bool = false

    // Optional proxy before login
    @State private var proxyEnabled: Bool = false
    @State private var proxyUrl: String = "http://127.0.0.1:7890"

    // Advanced toggle
    @State private var showAdvancedOptions: Bool = false
    @State private var manualAccessToken: String = ""
    @State private var manualAccountName: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "key.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
                    }
                    Text("Connect Claude Account")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Button {
                    cancelOAuthIfRunning()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Proxy settings section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("Use Proxy for this account", isOn: $proxyEnabled)
                                .font(.system(size: 12, weight: .medium))

                            Spacer()

                            if proxyEnabled {
                                Text("Enabled")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                        }

                        if proxyEnabled {
                            TextField("http://127.0.0.1:7890 or socks5://127.0.0.1:1080", text: $proxyUrl)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)

                    // Main OAuth Action Card
                    VStack(spacing: 12) {
                        if isStartingOAuth || isExchangingCode {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.regular)

                                Text(oauthStatusMessage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .multilineTextAlignment(.center)

                                if let port = currentPort {
                                    Text("Local callback server: http://localhost:\(port)/callback")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                if let authUrl = oauthAuthUrl {
                                    Button("Reopen Browser Tab") {
                                        NSWorkspace.shared.open(authUrl)
                                    }
                                    .buttonStyle(.link)
                                    .font(.system(size: 11))
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(8)
                        } else {
                            Button {
                                startOAuthFlow()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "safari")
                                    Text("Authorize in Browser (Claude.ai)")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.85, green: 0.47, blue: 0.34))
                            .controlSize(.large)
                        }

                        if let error = oauthErrorMessage {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                            .padding(8)
                        }
                    }

                    // Fallback manual code paste
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MANUAL CODE / REDIRECT URL (OPTIONAL FALLBACK)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Text("If the browser shows an authorization code or didn't auto-redirect:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Paste code or http://localhost:.../callback?code=...", text: $manualAuthCode)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

                            Button("Authorize") {
                                exchangeManualCode()
                            }
                            .buttonStyle(.bordered)
                            .disabled(manualAuthCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchangingCode)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // Advanced: Manual Access Token Import
                    DisclosureGroup(isExpanded: $showAdvancedOptions) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Account Name (e.g. Work Claude CLI)", text: $manualAccountName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))

                            TextField("Direct Access Token (eyJ...)", text: $manualAccessToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

                            Button("Add Token Directly") {
                                addDirectTokenAccount()
                            }
                            .buttonStyle(.bordered)
                            .disabled(manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Advanced: Import Access Token directly")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    cancelOAuthIfRunning()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 520, height: 460)
    }

    // MARK: - Actions

    private func startOAuthFlow() {
        isStartingOAuth = true
        oauthErrorMessage = nil
        oauthStatusMessage = "Starting local callback server..."

        let pkce = ClaudeOAuthService.generatePKCE()
        self.currentPKCE = pkce

        do {
            let (port, redirectUri) = try ClaudeOAuthService.shared.startLocalServer()
            self.currentPort = port
            self.currentRedirectUri = redirectUri

            guard let authUrl = ClaudeOAuthService.buildAuthorizeUrl(redirectUri: redirectUri, pkce: pkce) else {
                oauthErrorMessage = "Failed to construct authorization URL"
                isStartingOAuth = false
                return
            }

            self.oauthAuthUrl = authUrl
            oauthStatusMessage = "Opening browser... Please approve access on Claude.ai"

            // Open browser
            NSWorkspace.shared.open(authUrl)

            // Listen for callback in background
            Task {
                do {
                    oauthStatusMessage = "Waiting for approval in browser..."
                    let (code, _) = try await ClaudeOAuthService.shared.waitForCallback(timeoutSeconds: 300)

                    await MainActor.run {
                        self.isExchangingCode = true
                        self.oauthStatusMessage = "Exchanging code for tokens..."
                    }

                    let proxyConfig = proxyEnabled ? ProxyConfig(isEnabled: true, url: proxyUrl) : nil
                    let tokens = try await ClaudeOAuthService.shared.exchangeCode(
                        code: code,
                        redirectUri: redirectUri,
                        pkce: pkce,
                        proxy: proxyConfig
                    )

                    // Fetch bootstrap info
                    let bootstrap = try? await ClaudeOAuthService.shared.fetchBootstrap(
                        accessToken: tokens.accessToken,
                        proxy: proxyConfig
                    )

                    let newAccount = Account(
                        name: bootstrap?.organizationName ?? bootstrap?.accountEmail ?? "Claude Account",
                        email: bootstrap?.accountEmail,
                        organizationName: bootstrap?.organizationName,
                        accountUUID: bootstrap?.accountUuid,
                        plan: bootstrap?.parsedPlan,
                        accountType: bootstrap?.parsedAccountType,
                        rateLimitTier: bootstrap?.organizationRateLimitTier ?? bootstrap?.userRateLimitTier,
                        accessToken: tokens.accessToken,
                        refreshToken: tokens.refreshToken,
                        tokenExpiresAt: tokens.expiresIn != nil ? Date().addingTimeInterval(Double(tokens.expiresIn!)) : nil,
                        proxy: ProxyConfig(isEnabled: proxyEnabled, url: proxyUrl),
                        isMock: false,
                        status: .active,
                        usage: nil,
                        lastUpdated: nil
                    )

                    await MainActor.run {
                        store.addAccount(newAccount)
                        Task {
                            await store.refreshAccount(id: newAccount.id)
                        }
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        self.isStartingOAuth = false
                        self.isExchangingCode = false
                        self.oauthErrorMessage = "OAuth failed: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            isStartingOAuth = false
            oauthErrorMessage = "Failed to start local listener: \(error.localizedDescription)"
        }
    }

    private func exchangeManualCode() {
        guard let pkce = currentPKCE ?? Optional(ClaudeOAuthService.generatePKCE()) else { return }
        let redirectUri = currentRedirectUri ?? "http://localhost:54321/callback"
        var code = manualAuthCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if code.contains("code=") {
            if let comps = URLComponents(string: code),
               let c = comps.queryItems?.first(where: { $0.name == "code" })?.value {
                code = c
            }
        }

        isExchangingCode = true
        oauthErrorMessage = nil

        let proxyConfig = proxyEnabled ? ProxyConfig(isEnabled: true, url: proxyUrl) : nil

        Task {
            do {
                let tokens = try await ClaudeOAuthService.shared.exchangeCode(
                    code: code,
                    redirectUri: redirectUri,
                    pkce: pkce,
                    proxy: proxyConfig
                )

                let bootstrap = try? await ClaudeOAuthService.shared.fetchBootstrap(
                    accessToken: tokens.accessToken,
                    proxy: proxyConfig
                )

                let newAccount = Account(
                    name: bootstrap?.organizationName ?? bootstrap?.accountEmail ?? "Claude Account",
                    email: bootstrap?.accountEmail,
                    organizationName: bootstrap?.organizationName,
                    accountUUID: bootstrap?.accountUuid,
                    plan: bootstrap?.parsedPlan,
                    accountType: bootstrap?.parsedAccountType,
                    rateLimitTier: bootstrap?.organizationRateLimitTier ?? bootstrap?.userRateLimitTier,
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken,
                    tokenExpiresAt: tokens.expiresIn != nil ? Date().addingTimeInterval(Double(tokens.expiresIn!)) : nil,
                    proxy: ProxyConfig(isEnabled: proxyEnabled, url: proxyUrl),
                    isMock: false,
                    status: .active,
                    usage: nil,
                    lastUpdated: nil
                )

                await MainActor.run {
                    store.addAccount(newAccount)
                    Task {
                        await store.refreshAccount(id: newAccount.id)
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isExchangingCode = false
                    self.oauthErrorMessage = "Code exchange failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func addDirectTokenAccount() {
        let token = manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        let name = manualAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Claude Account" : name

        let newAccount = Account(
            name: finalName,
            accessToken: token,
            proxy: ProxyConfig(isEnabled: proxyEnabled, url: proxyUrl),
            isMock: false,
            status: .active,
            usage: nil,
            lastUpdated: nil
        )

        store.addAccount(newAccount)
        Task {
            await store.refreshAccount(id: newAccount.id)
        }
        dismiss()
    }

    private func cancelOAuthIfRunning() {
        ClaudeOAuthService.shared.stopLocalServer()
    }
}
