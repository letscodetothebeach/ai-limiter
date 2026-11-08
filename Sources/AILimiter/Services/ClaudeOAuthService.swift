import Foundation
import CryptoKit
import Darwin

public struct OAuthTokens: Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let tokenType: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

public struct BootstrapAccount: Codable {
    public let accountUuid: String?
    public let accountEmail: String?
    public let organizationUuid: String?
    public let organizationName: String?
    public let organizationType: String?
    public let organizationRateLimitTier: String?
    public let userRateLimitTier: String?
    public let seatTier: String?

    enum CodingKeys: String, CodingKey {
        case accountUuid = "account_uuid"
        case accountEmail = "account_email"
        case organizationUuid = "organization_uuid"
        case organizationName = "organization_name"
        case organizationType = "organization_type"
        case organizationRateLimitTier = "organization_rate_limit_tier"
        case userRateLimitTier = "user_rate_limit_tier"
        case seatTier = "seat_tier"
    }

    public var parsedPlan: String {
        let orgType = (organizationType ?? "").lowercased()
        let orgTier = (organizationRateLimitTier ?? "").lowercased()
        let userTier = (userRateLimitTier ?? "").lowercased()

        if orgType.contains("max") || orgTier.contains("max") || userTier.contains("max") {
            if orgTier.contains("20x") || userTier.contains("20x") {
                return "Max (20x)"
            } else if orgTier.contains("5x") || userTier.contains("5x") {
                return "Max (5x)"
            }
            return "Max"
        } else if orgType.contains("ultra") || orgTier.contains("ultra") || userTier.contains("ultra") {
            return "Ultra"
        } else if orgType.contains("pro") || orgTier.contains("pro") || orgTier.contains("claude_ai") {
            return "Pro"
        } else if orgType.contains("team") {
            return "Team"
        }
        return "Pro"
    }

    public var parsedAccountType: String {
        let orgType = (organizationType ?? "").lowercased()
        if orgType.contains("team") || orgType.contains("business") || orgType.contains("enterprise") {
            return "Business"
        }
        if let orgName = organizationName, !orgName.contains("'s Organization") && !orgName.lowercased().contains("personal") {
            return "Business"
        }
        return "Personal"
    }
}

public struct BootstrapResponse: Codable {
    public let oauthAccount: BootstrapAccount?

    enum CodingKeys: String, CodingKey {
        case oauthAccount = "oauth_account"
    }
}

public struct PKCEPair: Sendable {
    public let verifier: String
    public let challenge: String
    public let state: String
}

@MainActor
public final class ClaudeOAuthService {
    public static let shared = ClaudeOAuthService()

    public static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeBaseUrl = "https://claude.ai/oauth/authorize"
    public static let tokenUrl = "https://api.anthropic.com/v1/oauth/token"
    public static let bootstrapUrl = "https://api.anthropic.com/api/claude_cli/bootstrap"
    public static let scopes = ["org:create_api_key", "user:profile", "user:inference"]

    private var activeServerFd: Int32 = -1
    private var isListening = false

    public init() {}

    // MARK: - PKCE Helpers

    public static func generatePKCE() -> PKCEPair {
        var verifierBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &verifierBytes)
        let verifier = base64URLEncode(Data(verifierBytes))

        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = base64URLEncode(Data(hash))

        var stateBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &stateBytes)
        let state = base64URLEncode(Data(stateBytes))

        return PKCEPair(verifier: verifier, challenge: challenge, state: state)
    }

    public static func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    // MARK: - Auth URL Builder

    public static func buildAuthorizeUrl(redirectUri: String, pkce: PKCEPair) -> URL? {
        var components = URLComponents(string: authorizeBaseUrl)
        let scopeString = scopes.joined(separator: " ")

        components?.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopeString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state)
        ]

        return components?.url
    }

    // MARK: - Loopback Server for OAuth Callback

    /// Starts a local HTTP server on 127.0.0.1 on an ephemeral port.
    /// Returns the port and a continuation to wait for the authorization callback.
    public func startLocalServer() throws -> (port: UInt16, redirectUri: String) {
        stopLocalServer()

        let serverFd = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            throw NSError(domain: "ClaudeOAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }

        var opt: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = in_port_t(0) // kernel assigns ephemeral port
        sin.sin_addr.s_addr = inet_addr("127.0.0.1")

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bindResult = withUnsafeMutablePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(serverFd, saPtr, len)
            }
        }

        guard bindResult == 0 else {
            close(serverFd)
            throw NSError(domain: "ClaudeOAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket to 127.0.0.1"])
        }

        guard listen(serverFd, 5) == 0 else {
            close(serverFd)
            throw NSError(domain: "ClaudeOAuth", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen on socket"])
        }

        _ = withUnsafeMutablePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                getsockname(serverFd, saPtr, &len)
            }
        }

        let port = UInt16(bigEndian: sin.sin_port)
        self.activeServerFd = serverFd
        self.isListening = true

        let redirectUri = "http://localhost:\(port)/callback"
        return (port, redirectUri)
    }

    public func stopLocalServer() {
        if activeServerFd >= 0 {
            close(activeServerFd)
            activeServerFd = -1
        }
        isListening = false
    }

    /// Waits asynchronously on a background thread for the callback request from the browser.
    public func waitForCallback(timeoutSeconds: TimeInterval = 300) async throws -> (code: String, state: String?) {
        let fd = self.activeServerFd

        guard fd >= 0 else {
            throw NSError(domain: "ClaudeOAuth", code: 4, userInfo: [NSLocalizedDescriptionKey: "Server not running"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var clientSin = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                // Poll or block on accept
                var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0)]
                let pollResult = poll(&fds, 1, Int32(timeoutSeconds * 1000))

                guard pollResult > 0, (fds[0].revents & Int16(POLLIN)) != 0 else {
                    Task { @MainActor in self?.stopLocalServer() }
                    continuation.resume(throwing: NSError(domain: "ClaudeOAuth", code: 5, userInfo: [NSLocalizedDescriptionKey: "Authentication timed out"]))
                    return
                }

                let clientFd = withUnsafeMutablePointer(to: &clientSin) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        accept(fd, saPtr, &clientLen)
                    }
                }

                guard clientFd >= 0 else {
                    Task { @MainActor in self?.stopLocalServer() }
                    continuation.resume(throwing: NSError(domain: "ClaudeOAuth", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to accept client connection"]))
                    return
                }

                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = read(clientFd, &buffer, 4096)
                guard bytesRead > 0, let requestStr = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) else {
                    close(clientFd)
                    Task { @MainActor in self?.stopLocalServer() }
                    continuation.resume(throwing: NSError(domain: "ClaudeOAuth", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to read request from browser"]))
                    return
                }

                // Parse the GET line: e.g. GET /callback?code=...&state=... HTTP/1.1
                let lines = requestStr.components(separatedBy: "\r\n")
                guard let firstLine = lines.first else {
                    close(clientFd)
                    Task { @MainActor in self?.stopLocalServer() }
                    continuation.resume(throwing: NSError(domain: "ClaudeOAuth", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP request line"]))
                    return
                }

                let parts = firstLine.components(separatedBy: " ")
                guard parts.count >= 2 else {
                    close(clientFd)
                    Task { @MainActor in self?.stopLocalServer() }
                    continuation.resume(throwing: NSError(domain: "ClaudeOAuth", code: 9, userInfo: [NSLocalizedDescriptionKey: "Malformed HTTP request"]))
                    return
                }

                let pathAndQuery = parts[1]
                var codeParam: String?
                var stateParam: String?
                var errorParam: String?

                if let urlComponents = URLComponents(string: "http://localhost" + pathAndQuery) {
                    codeParam = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value
                    stateParam = urlComponents.queryItems?.first(where: { $0.name == "state" })?.value
                    errorParam = urlComponents.queryItems?.first(where: { $0.name == "error" })?.value
                }

                // Send friendly response HTML back to browser
                let html = """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <title>Claude Limit Tracker - Authentication</title>
                    <style>
                        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #0f1117; color: #f0f0f0; }
                        .card { text-align: center; padding: 2.5rem 3rem; background: #1a1d26; border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); border: 1px solid #2a2f3d; max-width: 440px; }
                        .icon { font-size: 3.5rem; margin-bottom: 1rem; color: #D97757; }
                        h1 { font-size: 1.5rem; margin-bottom: 0.5rem; color: #ffffff; }
                        p { color: #9ca3af; font-size: 0.95rem; line-height: 1.5; }
                        .badge { display: inline-block; background: #D97757; color: white; padding: 4px 12px; border-radius: 9999px; font-size: 0.8rem; font-weight: bold; margin-top: 1rem; }
                    </style>
                </head>
                <body>
                    <div class="card">
                        <div class="icon">✨</div>
                        <h1>Claude Connected!</h1>
                        <p>Authorization code received. You can now close this tab and return to <strong>Claude Limit Tracker</strong>.</p>
                        <div class="badge">Success</div>
                    </div>
                    <script>
                        setTimeout(() => { window.close(); }, 2500);
                    </script>
                </body>
                </html>
                """

                let responseHeaders = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n"
                let fullResponse = responseHeaders + html

                _ = fullResponse.withCString { cstr in
                    write(clientFd, cstr, strlen(cstr))
                }
                close(clientFd)
                Task { @MainActor in self?.stopLocalServer() }

                if let err = errorParam {
                    continuation.resume(throwing: NSError(domain: "ClaudeOAuth", code: 10, userInfo: [NSLocalizedDescriptionKey: "Anthropic returned error: \(err)"]))
                    return
                }

                guard let code = codeParam, !code.isEmpty else {
                    continuation.resume(throwing: NSError(domain: "ClaudeOAuth", code: 11, userInfo: [NSLocalizedDescriptionKey: "No authorization code found in callback query"]))
                    return
                }

                continuation.resume(returning: (code, stateParam))
            }
        }
    }

    // MARK: - Code Exchange for Tokens

    /// Exchanges authorization code for access and refresh tokens.
    /// Handles code strings that might contain `#state` (e.g. `code#state`).
    public func exchangeCode(
        code: String,
        redirectUri: String,
        pkce: PKCEPair,
        proxy: ProxyConfig? = nil
    ) async throws -> OAuthTokens {
        // Parse code in case it includes state after # (Claude behavior noted in llm-hub)
        var authCode = code
        var codeState = pkce.state
        if authCode.contains("#") {
            let parts = authCode.components(separatedBy: "#")
            authCode = parts[0]
            if parts.count > 1 && !parts[1].isEmpty {
                codeState = parts[1]
            }
        }

        let payload: [String: Any] = [
            "code": authCode,
            "state": codeState,
            "grant_type": "authorization_code",
            "client_id": Self.clientId,
            "redirect_uri": redirectUri,
            "code_verifier": pkce.verifier
        ]

        guard let tokenEndpoint = URL(string: Self.tokenUrl) else {
            throw NSError(domain: "ClaudeOAuth", code: 12, userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let session = ProxySessionManager.shared.session(for: proxy)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ClaudeOAuth", code: 13, userInfo: [NSLocalizedDescriptionKey: "Invalid response from token server"])
        }

        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "ClaudeOAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(errorText)"])
        }

        let tokens = try JSONDecoder().decode(OAuthTokens.self, from: data)
        return tokens
    }

    // MARK: - Refresh Token

    /// Refreshes an expired access token using the refresh_token grant.
    public func refreshToken(
        refreshToken: String,
        proxy: ProxyConfig? = nil
    ) async throws -> OAuthTokens {
        guard let tokenEndpoint = URL(string: Self.tokenUrl) else {
            throw NSError(domain: "ClaudeOAuth", code: 14, userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
        }

        let payload: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientId
        ]

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let session = ProxySessionManager.shared.session(for: proxy)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ClaudeOAuth", code: 15, userInfo: [NSLocalizedDescriptionKey: "Invalid response while refreshing token"])
        }

        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "ClaudeOAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed: \(errorText)"])
        }

        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    // MARK: - Bootstrap Account Info

    /// Fetches account email and organization name via Claude CLI bootstrap endpoint.
    public func fetchBootstrap(
        accessToken: String,
        proxy: ProxyConfig? = nil
    ) async throws -> BootstrapAccount? {
        guard let bootstrapEndpoint = URL(string: Self.bootstrapUrl) else {
            return nil
        }

        var request = URLRequest(url: bootstrapEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-cli/0.2.29 (external, cli)", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let session = ProxySessionManager.shared.session(for: proxy)
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let res = try JSONDecoder().decode(BootstrapResponse.self, from: data)
            return res.oauthAccount
        } catch {
            return nil
        }
    }
}
