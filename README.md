# AI Limiter

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/letscodetothebeach/ai-limiter?include_prereleases&color=purple)](https://github.com/letscodetothebeach/ai-limiter/releases)

**AI Limiter** is a lightweight, high-density native macOS menu and window utility built with Swift and SwiftUI. It gives developers a real-time, consolidated overview of subscription quota windows (5-hour session limits and 7-day rolling limits) across multiple AI accounts from a single screen.

Designed with an ultra-compact layout, AI Limiter displays dozens of accounts at a glance without clutter, enabling smooth workflow planning and eliminating unexpected rate limits during intensive coding sessions.

---

## 🌟 Key Features

- **High-Density Compact Dashboard**:
  - Displays 15–20+ accounts on a single screen without vertical scrolling (~48px per row).
  - Clear row index badges (`1`, `2`, `3`, `4`...) for instant identification.
  - Quick-action buttons directly on each row for instant refresh, proxy setup, and removal.
- **Drag & Drop Reordering**:
  - Rearrange account rows effortlessly using the drag handle (`≡`).
  - Custom order is automatically saved and persisted across launches.
- **Real-Time Quota & Reset Timers**:
  - **5-Hour Session Limit**: Visual meter, percentage consumed, and exact countdown timer to quota reset (e.g., `32% • 2h 15m`).
  - **7-Day Weekly Limit**: Compact progress bar, utilization %, and countdown reset timer (e.g., `48% • 4d`).
  - Dynamic status indicators: Green (< 60%), Amber (60%–85%), and Red (≥ 85%).
- **Per-Account Proxy Routing & Latency Benchmarks**:
  - Assign individual HTTP, HTTPS, or SOCKS5 proxies (`http://127.0.0.1:7890`, `socks5://127.0.0.1:1080`) to specific accounts.
  - Built-in latency tester with live ping diagnostics.
  - Proxies can be toggled on/off instantly per row.
- **State Persistence**:
  - Auto-refresh settings (enabled state, refresh intervals: 1m, 5m, 15m) are persisted in `UserDefaults`.
  - Account ordering, credentials, and proxy setups are stored locally on your Mac.
- **Secure Local-Only Authentication**:
  - Standard OAuth PKCE authorization with local loopback listener (`http://127.0.0.1:<port>/callback`).
  - Manual authorization code fallback for headless or restricted environments.
  - All tokens and configurations are saved strictly locally at `~/Library/Application Support/AILimiter/`. Zero external servers, zero analytics, zero telemetry.
- **Extensible Architecture**:
  - Clean domain separation ready to support additional AI provider harnesses.

---

## 💡 Use Cases

AI Limiter is purely an observability utility designed to make developer life easier:

1. **Multi-Project & Workspace Tracking**: Developers maintaining separate subscriptions for personal experiments, client work, or organizational workspaces can monitor usage side-by-side without repetitive browser logins.
2. **Preventing Mid-Task Interruptions**: Know your remaining quota and reset window before kicking off large automated refactoring jobs or agentic generation runs.
3. **Network Diagnostics**: Easily verify whether corporate proxies or local development tunnels are functioning properly with built-in connection latency checks.
4. **Subscription Quota Awareness**: Ensure you are getting the full value of your tiers while staying well within rate limits.

---

## 📥 Installation

### Download Disk Image (.dmg)

1. Head to the [Releases](https://github.com/letscodetothebeach/ai-limiter/releases) page.
2. Download the latest `AI-Limiter.dmg`.
3. Open the disk image and drag **AI Limiter** into your **Applications** folder.
4. Launch **AI Limiter** from Launchpad or Spotlight.

> [!NOTE]
> If macOS Gatekeeper displays *"AI Limiter is damaged and can't be opened"*, this occurs because the binary downloaded from the web is not notarized by Apple. You can clear the quarantine attribute by running:
> ```bash
> xattr -cr "/Applications/AI Limiter.app"
> ```

### Build from Source

Requirements: macOS 13.0+ and Xcode 15+ / Swift 6 toolchain.

```bash
# Clone the repository
git clone https://github.com/letscodetothebeach/ai-limit-track.git
cd ai-limit-track

# Run unit tests
swift test

# Build the release app bundle (.app)
./build-app.sh

# Optional: Build and sign with your Apple Developer identity
# SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" ./build-app.sh

# Build a distributable DMG (.dmg)
./build-dmg.sh

# Launch the app
open "AI Limiter.app"
```

---

## 🖥️ User Interface Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│  AI LIMITER   [6 accounts]            [Auto-Refresh: ON 5m ▾] [⟳ Refresh] [ + Connect ]
├────┬──────────────────┬──────────────────┬──────────────────┬──────────┬───────┤
│ #  │ ACCOUNT          │ 5-HOUR LIMIT     │ 7-DAY LIMIT      │ PROXY    │ ACT.  │
├────┼──────────────────┼──────────────────┼──────────────────┼──────────┼───────┤
│ 1  │ ≡ Team Core      │ [████      ] 42% │ [██████    ] 65% │ [🟢 7890]│ ⟳  ⚙  │
│ 2  │ ≡ Client Project │ [█         ] 12% │ [███       ] 28% │ [Direct] │ ⟳  ⚙  │
│ 3  │ ≡ Personal Dev   │ [█████████ ] 88% │ [████      ] 40% │ [🟢 S5]  │ ⟳  ⚙  │
└────┴──────────────────┴──────────────────┴──────────────────┴──────────┴───────┘
```

- **Drag Handle (`≡`)**: Click and drag to reorder.
- **Row Index (`#`)**: Shows exact row position (`1`, `2`, `3`...).
- **5-Hour Limit Bar**: Highlights short-term session consumption.
- **7-Day Limit Bar**: Highlights weekly quota consumption.
- **Proxy Badge**: Click to inspect proxy settings, toggle proxy on/off, or test connection latency.
- **Actions**: Trigger an immediate single-account refresh or remove the account.

---

## 🔒 Privacy & Security

- **Local Storage Only**: Accounts and tokens are stored in plain JSON under the user's application support directory: `~/Library/Application Support/AILimiter/accounts.json`.
- **No Third-Party Analytics**: AI Limiter does not include tracking SDKs, crash analytics, or external telemetry of any kind.
- **Direct API Calls**: Network requests are dispatched exclusively to official AI provider endpoints or through the user's explicitly configured local proxy.

---

## 🛠️ Tech Stack & Architecture

- **Language**: Swift 6 (strict concurrency compliance, `@MainActor` state management).
- **Framework**: SwiftUI on macOS (AppKit integration where native system APIs are required).
- **Networking**: `URLSession` with low-level `CFNetwork` proxy configurations (`kCFNetworkProxiesHTTPEnable`, `kCFStreamPropertySOCKSProxy`).
- **Authentication**: RFC 7636 PKCE OAuth flow with dynamic local loopback HTTP server.
- **Testing**: Swift Testing framework (`import Testing`).

---

## 🤝 Contributing

Contributions are welcome! Please review [AGENTS.md](AGENTS.md) for architectural guidelines, testing patterns, and coding standards.

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/my-feature`).
3. Ensure all tests pass (`swift test`).
4. Commit your changes (`git commit -m 'feat: add my feature'`).
5. Push to the branch (`git push origin feature/my-feature`).
6. Open a Pull Request.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
