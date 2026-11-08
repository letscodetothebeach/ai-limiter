import SwiftUI
import AppKit

public struct ReauthSheet: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    public let account: Account

    @State private var isStartingOAuth: Bool = false
    @State private var isExchangingCode: Bool = false
    @State private var oauthStatusMessage: String = "Starting authorization..."
    @State private var currentPort: UInt16? = nil
    @State private var currentRedirectUri: String? = nil
    @State private var currentPKCE: PKCEPair? = nil
    @State private var authUrl: URL? = nil
    @State private var manualAuthCode: String = ""
    @State private var oauthErrorMessage: String? = nil
    @State private var isCopiedAuthLink: Bool = false

    // Proxy support (inherited from account)
    @State private var proxyEnabled: Bool = false
    @State private var proxyUrl: String = ""

    // Advanced manual token fallback
    @State private var showAdvancedOptions: Bool = false
    @State private var manualAccessToken: String = ""

    public init(account: Account) {
        self.account = account
        _proxyEnabled = State(initialValue: account.proxy.isEnabled)
        _proxyUrl = State(initialValue: account.proxy.url)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Re-authenticate Account")
                            .font(.system(size: 15, weight: .bold))
                        HStack(spacing: 6) {
                            Text(account.cleanDisplayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                            if let email = account.email, !email.isEmpty {
                                Text("(\(email))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Spacer()
                Button {
                    cancelOAuthIfRunning()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Reason for Reauth / Error summary banner
                    if let errorMsg = account.status.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Current Issue:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.red)
                                Text(errorMsg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                Text("Re-authenticating will request a new OAuth token from Claude.ai and restore quota tracking.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // Mock Account Banner
                    if account.isMock {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                                .font(.system(size: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mock Account Mode")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.purple)
                                Text("This is a simulated account. You can test resolving the error instantly:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Button("Simulate Successful Re-auth") {
                                    simulateMockSuccess()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .controlSize(.small)
                                .padding(.top, 2)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // Proxy configuration section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("Route through proxy", isOn: $proxyEnabled)
                                .font(.system(size: 12, weight: .medium))

                            Spacer()

                            if proxyEnabled {
                                Text("Proxy Active")
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

                    // Main Authorization Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            if isStartingOAuth || isExchangingCode {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(oauthStatusMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        // Prominent Authorization Link Box
                        if let url = authUrl {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                            .font(.system(size: 10))
                                        Text("AUTHORIZATION LINK")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(.secondary)

                                    Spacer()

                                    if isCopiedAuthLink {
                                        HStack(spacing: 3) {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Copied to clipboard!")
                                        }
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                    }
                                }

                                Text(url.absoluteString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                    .textSelection(.enabled)

                                HStack(spacing: 8) {
                                    Button {
                                        copyAuthLink(url)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: isCopiedAuthLink ? "checkmark" : "doc.on.doc")
                                            Text(isCopiedAuthLink ? "Copied" : "Copy Auth Link")
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "safari")
                                            Text("Open in Browser")
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Spacer()

                                    if let port = currentPort {
                                        Text("Port: \(port)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.blue.opacity(0.07))
                            .cornerRadius(8)
                        } else {
                            Button {
                                startOAuthFlow()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "safari")
                                    Text("Start Authorization in Browser")
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
                            .background(Color.red.opacity(0.06))
                            .cornerRadius(6)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // Fallback manual code paste
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MANUAL CODE / REDIRECT URL (FALLBACK)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Text("If the browser showed an authorization code or did not automatically redirect to localhost:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Paste code or http://localhost:.../callback?code=...", text: $manualAuthCode)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

                            Button("Complete Reauth") {
                                exchangeManualCode()
                            }
                            .buttonStyle(.bordered)
                            .disabled(manualAuthCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchangingCode)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // Advanced: Direct Access Token update
                    DisclosureGroup(isExpanded: $showAdvancedOptions) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you already have a valid OAuth access token, you can paste it directly:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            TextField("Direct Access Token (sk-ant-...) or (eyJ...)", text: $manualAccessToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

                            Button("Update Token Directly") {
                                updateDirectToken()
                            }
                            .buttonStyle(.bordered)
                            .disabled(manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Advanced: Paste Access Token directly")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    cancelOAuthIfRunning()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if authUrl != nil && !isExchangingCode {
                    Button("Restart Flow") {
                        cancelOAuthIfRunning()
                        startOAuthFlow()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 540, height: 500)
        .onAppear {
            if !account.isMock {
                startOAuthFlow()
            }
        }
        .onDisappear {
            cancelOAuthIfRunning()
        }
    }

    // MARK: - Actions

    private func copyAuthLink(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        withAnimation {
            isCopiedAuthLink = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                isCopiedAuthLink = false
            }
        }
    }

    private func startOAuthFlow() {
        isStartingOAuth = true
        oauthErrorMessage = nil
        oauthStatusMessage = "Starting local server..."

        let pkce = ClaudeOAuthService.generatePKCE()
        self.currentPKCE = pkce

        do {
            let (port, redirectUri) = try ClaudeOAuthService.shared.startLocalServer()
            self.currentPort = port
            self.currentRedirectUri = redirectUri

            guard let url = ClaudeOAuthService.buildAuthorizeUrl(redirectUri: redirectUri, pkce: pkce) else {
                oauthErrorMessage = "Failed to construct authorization URL"
                isStartingOAuth = false
                return
            }

            self.authUrl = url
            oauthStatusMessage = "Waiting for approval in browser... Use the link below if it doesn't open."

            // Auto-open browser
            NSWorkspace.shared.open(url)

            // Listen for callback in background
            Task {
                do {
                    let (code, _) = try await ClaudeOAuthService.shared.waitForCallback(timeoutSeconds: 300)

                    await MainActor.run {
                        self.isExchangingCode = true
                        self.oauthStatusMessage = "Exchanging authorization code for tokens..."
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

                    await MainActor.run {
                        if proxyEnabled != account.proxy.isEnabled || proxyUrl != account.proxy.url {
                            store.setProxy(for: account.id, isEnabled: proxyEnabled, url: proxyUrl)
                        }

                        store.updateAccountTokens(
                            id: account.id,
                            accessToken: tokens.accessToken,
                            refreshToken: tokens.refreshToken,
                            tokenExpiresAt: tokens.expiresIn != nil ? Date().addingTimeInterval(Double(tokens.expiresIn!)) : nil,
                            bootstrap: bootstrap
                        )

                        Task {
                            await store.refreshAccount(id: account.id)
                        }
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        self.isStartingOAuth = false
                        self.isExchangingCode = false
                        self.oauthErrorMessage = "Authorization failed: \(error.localizedDescription)"
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

                await MainActor.run {
                    if proxyEnabled != account.proxy.isEnabled || proxyUrl != account.proxy.url {
                        store.setProxy(for: account.id, isEnabled: proxyEnabled, url: proxyUrl)
                    }

                    store.updateAccountTokens(
                        id: account.id,
                        accessToken: tokens.accessToken,
                        refreshToken: tokens.refreshToken,
                        tokenExpiresAt: tokens.expiresIn != nil ? Date().addingTimeInterval(Double(tokens.expiresIn!)) : nil,
                        bootstrap: bootstrap
                    )

                    Task {
                        await store.refreshAccount(id: account.id)
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

    private func updateDirectToken() {
        let token = manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        store.updateAccountTokens(
            id: account.id,
            accessToken: token,
            refreshToken: nil,
            tokenExpiresAt: nil,
            bootstrap: nil
        )

        Task {
            await store.refreshAccount(id: account.id)
        }
        dismiss()
    }

    private func simulateMockSuccess() {
        guard let index = store.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        store.accounts[index].status = .active
        store.accounts[index].usage = ClaudeUsageService.shared.generateMockUsage(for: account, scenario: .normal)
        store.accounts[index].lastUpdated = Date()
        store.saveAccounts()
        dismiss()
    }

    private func cancelOAuthIfRunning() {
        ClaudeOAuthService.shared.stopLocalServer()
    }
}
