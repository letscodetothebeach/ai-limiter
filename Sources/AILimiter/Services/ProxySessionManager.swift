import Foundation
import CFNetwork

public struct ProxyTestResult: Equatable {
    public let isSuccess: Bool
    public let message: String
    public let latencyMs: Double?
    
    public init(isSuccess: Bool, message: String, latencyMs: Double? = nil) {
        self.isSuccess = isSuccess
        self.message = message
        self.latencyMs = latencyMs
    }
}

public final class ProxySessionManager: Sendable {
    public static let shared = ProxySessionManager()

    public init() {}

    /// Creates a URLSessionConfiguration based on the provided ProxyConfig.
    /// If proxy is disabled or invalid, returns a standard ephemeral configuration.
    public func createSessionConfiguration(for proxy: ProxyConfig?) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0

        guard let proxy = proxy, proxy.isEnabled, !proxy.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return config
        }

        guard let proxyDict = buildProxyDictionary(from: proxy.url) else {
            return config
        }

        config.connectionProxyDictionary = proxyDict
        return config
    }

    /// Creates a URLSession configured with the given proxy configuration.
    public func session(for proxy: ProxyConfig?) -> URLSession {
        let config = createSessionConfiguration(for: proxy)
        return URLSession(configuration: config)
    }

    /// Builds the CFNetwork proxy dictionary from a URL string like "http://127.0.0.1:7890" or "socks5://127.0.0.1:1080".
    public func buildProxyDictionary(from rawUrlString: String) -> [AnyHashable: Any]? {
        var trimmed = rawUrlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") {
            // Default to http scheme if none specified
            trimmed = "http://" + trimmed
        }

        guard let url = URL(string: trimmed), let host = url.host else {
            return nil
        }

        var dict: [AnyHashable: Any] = [:]
        let scheme = (url.scheme ?? "http").lowercased()

        if scheme.hasPrefix("socks") {
            let port = url.port ?? 1080
            dict[kCFStreamPropertySOCKSProxy as String] = 1
            dict[kCFStreamPropertySOCKSProxyHost as String] = host
            dict[kCFStreamPropertySOCKSProxyPort as String] = port

            if let user = url.user {
                dict[kCFStreamPropertySOCKSUser as String] = user
            }
            if let password = url.password {
                dict[kCFStreamPropertySOCKSPassword as String] = password
            }
        } else {
            // HTTP / HTTPS Proxy
            let port = url.port ?? (scheme == "https" ? 443 : 8080)
            
            dict[kCFNetworkProxiesHTTPEnable as String] = 1
            dict[kCFNetworkProxiesHTTPProxy as String] = host
            dict[kCFNetworkProxiesHTTPPort as String] = port

            dict[kCFNetworkProxiesHTTPSEnable as String] = 1
            dict[kCFNetworkProxiesHTTPSProxy as String] = host
            dict[kCFNetworkProxiesHTTPSPort as String] = port
        }

        return dict
    }

    /// Tests whether the proxy can reach Anthropic or an external endpoint.
    public func testProxy(proxyUrl: String) async -> ProxyTestResult {
        let trimmed = proxyUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ProxyTestResult(isSuccess: false, message: "Proxy URL is empty")
        }

        guard let _ = buildProxyDictionary(from: trimmed) else {
            return ProxyTestResult(isSuccess: false, message: "Invalid proxy URL format")
        }

        let proxyConfig = ProxyConfig(isEnabled: true, url: trimmed)
        let session = self.session(for: proxyConfig)

        guard let testUrl = URL(string: "https://api.anthropic.com") else {
            return ProxyTestResult(isSuccess: false, message: "Invalid test target URL")
        }

        var request = URLRequest(url: testUrl)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8.0

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await session.data(for: request)
            let latencyMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

            if let httpResponse = response as? HTTPURLResponse {
                // Any response from Anthropic server (even 404/403) confirms connectivity through the proxy
                return ProxyTestResult(
                    isSuccess: true,
                    message: "Connected! Status: \(httpResponse.statusCode)",
                    latencyMs: latencyMs
                )
            } else {
                return ProxyTestResult(isSuccess: true, message: "Proxy reached endpoint", latencyMs: latencyMs)
            }
        } catch {
            let latencyMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            return ProxyTestResult(
                isSuccess: false,
                message: "Connection failed: \(error.localizedDescription)",
                latencyMs: latencyMs
            )
        }
    }
}
