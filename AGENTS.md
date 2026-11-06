# Developer & Agent Guidelines (AGENTS.md)

This document provides conventions, architecture notes, and verification standards for AI coding agents and human engineers contributing to **AI Limiter**.

---

## 🧭 Project Philosophy & Scope

1. **Observability Only**: AI Limiter is an observability dashboard for developers to track subscription limits (5-hour and 7-day quotas) across multiple accounts to prevent unexpected workflow disruptions. It does not perform quota evasion, credential scraping, or unauthorized access.
2. **Local-First & Zero Telemetry**: All tokens, preferences, and proxy configurations must remain strictly local on the user's machine (`~/Library/Application Support/AILimiter/`). Never add external analytics or remote telemetry.
3. **High Density**: The UI must maintain a compact, high-density format (~48px per row) allowing 15+ accounts to be visible simultaneously without needless vertical bloat.
4. **Harness Agnostic**: While initial support is focused on standard OAuth usage limits, the models and services are structured to cleanly accommodate additional AI providers.

---

## 🏗️ Architecture & Directory Layout

```
Sources/AILimiter/
├── AILimiterApp.swift          # App entry point (@main, Settings scene, NSApplication setup)
├── Models/
│   └── Account.swift          # Core data models (Account, QuotaWindow, UsageData, ProxyConfig, AccountStatus)
├── Services/
│   ├── ClaudeOAuthService.swift     # PKCE generation, local loopback listener (NWListener), token exchange/refresh
│   ├── ClaudeUsageService.swift     # Usage limit API client, rate-limit backoff handling, mock generator
│   └── ProxySessionManager.swift    # CFNetwork-backed URLSessionConfiguration, latency ping tester
├── Store/
│   └── AccountStore.swift           # @MainActor central state, auto-refresh timer, disk & UserDefaults persistence
├── Components/
│   ├── CompactQuotaMeter.swift      # High-density quota bar with utilization % and reset countdown
│   ├── QuotaBarView.swift           # Standard linear quota meter
│   └── CircularQuotaView.swift      # Circular gauge visualization
└── Views/
    ├── ContentView.swift            # Main window, top toolbar, column headers, Drag & Drop list
    ├── AccountRowView.swift         # ~48px row: index badge, drag handle, quotas, proxy popover, actions
    ├── AccountCardView.swift        # Expanded card format (alternative view)
    └── AddAccountSheet.swift        # Account connection modal (OAuth browser flow + manual code fallback)

Tests/AILimiterTests/
└── AILimiterTests.swift       # Swift Testing suite covering PKCE, proxy config, JSON parsing, CRUD, reordering
```

---

## ⚙️ Development & Testing Workflow

### Building & Running
```bash
# Build the project
swift build

# Run directly via CLI
swift run

# Run unit tests
swift test
```

### Packaging Releases
```bash
# Generate icon (if needed)
swift generate-icon.swift

# Build the release .app bundle
./build-app.sh

# Build the distributable .dmg disk image
./build-dmg.sh
```

---

## 📋 Concurrency & Code Style Standards

1. **Swift 6 Strict Concurrency**:
   - `AccountStore`, `ClaudeOAuthService`, and `ClaudeUsageService` are isolated to `@MainActor`.
   - All models (`Account`, `QuotaWindow`, `ProxyConfig`, `UsageData`) must conform to `Sendable`, `Codable`, `Identifiable`, and `Equatable`.
   - Never use manual locks (`NSLock`) across asynchronous suspension points.
2. **Ephemeral Network Sessions**:
   - Always create custom `URLSession` instances with ephemeral configurations through `ProxySessionManager.shared.session(for: proxyConfig)` to avoid proxy caching leaks or cross-account connection reuse.
3. **Error Handling**:
   - Network errors must not crash the app or block UI updates for other accounts. Each account tracks its own `AccountStatus` (`.idle`, `.refreshing`, `.error(String)`, `.coolingDown(Date)`).
4. **State Persistence**:
   - Accounts are persisted to `~/Library/Application Support/AILimiter/accounts.json`.
   - UI toggles (auto-refresh, interval) are persisted to `UserDefaults`.

---

## 🧪 Testing Requirements

Any changes or additions to network logic, parsing, or store state **must** include corresponding tests in `Tests/AILimiterTests/AILimiterTests.swift`.

Always verify that `swift test` exits cleanly with zero failures before committing changes.
