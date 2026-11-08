import SwiftUI

// MARK: - Badges

struct AccountTypeBadge: View {
    let type: String

    var isPersonal: Bool {
        type.lowercased() == "personal"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isPersonal ? "person.fill" : "building.2.fill")
                .font(.system(size: 8))
            Text(type)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(isPersonal ? .blue : .purple)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(isPersonal ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
        .cornerRadius(4)
        .fixedSize()
    }
}

struct AccountPlanBadge: View {
    let plan: String

    private var badgeColor: Color {
        let lower = plan.lowercased()
        if lower.contains("ultra") { return .pink }
        if lower.contains("max") { return Color(red: 0.95, green: 0.55, blue: 0.15) }
        if lower.contains("pro") { return .teal }
        if lower.contains("team") { return .indigo }
        return .orange
    }

    private var badgeIcon: String {
        let lower = plan.lowercased()
        if lower.contains("ultra") { return "sparkles" }
        if lower.contains("max") { return "bolt.fill" }
        if lower.contains("pro") { return "star.fill" }
        if lower.contains("team") { return "person.2.fill" }
        return "tag.fill"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: badgeIcon)
                .font(.system(size: 8, weight: .bold))
            Text(plan)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.13))
        .cornerRadius(4)
        .fixedSize()
    }
}

public struct AccountRowView: View {
    @EnvironmentObject var store: AccountStore
    public let account: Account
    public let index: Int

    @State private var isEditingName: Bool = false
    @State private var editedName: String = ""
    @State private var isShowingDeleteConfirmation: Bool = false
    @State private var isShowingProxyPopover: Bool = false
    @State private var isShowingStatusPopover: Bool = false

    // Local proxy state for popover editing
    @State private var localProxyEnabled: Bool = false
    @State private var localProxyUrl: String = ""
    @State private var isTestingProxy: Bool = false
    @State private var proxyTestMessage: String? = nil
    @State private var proxyTestSuccess: Bool? = nil

    public init(account: Account, index: Int = 0) {
        self.account = account
        self.index = index
    }

    private var statusColor: Color {
        switch account.status {
        case .active: return .green
        case .refreshing: return .blue
        case .rateLimited: return .orange
        case .expired: return .yellow
        case .error: return .red
        }
    }

    private var statusTooltipText: String {
        switch account.status {
        case .error(let msg):
            return "🔴 Connection Error: \(msg)\nClick to view details & re-authenticate"
        case .expired:
            return "🟡 Token Expired\nClick to re-authenticate"
        case .rateLimited(let resetsAt):
            if let resetsAt = resetsAt {
                let diff = max(0, Int(resetsAt.timeIntervalSince(Date())))
                return "🟠 Rate Limited (429) - Cooldown: \(diff)s remaining"
            }
            return "🟠 Rate Limited (429)"
        case .refreshing:
            return "🔵 Refreshing account limits..."
        case .active:
            return "🟢 Status: Active (Connected successfully)"
        }
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Drag Handle & Row Index (1, 2, 3...)
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.55))
                    .help("Drag to reorder")

                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 24)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
            }
            .frame(width: 44, alignment: .leading)

            // Status Indicator (Clickable with rich Popover & Tooltip)
            Button {
                isShowingStatusPopover.toggle()
            } label: {
                ZStack {
                    if case .error = account.status {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red)
                    } else if case .expired = account.status {
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.yellow)
                    } else if case .rateLimited = account.status {
                        Image(systemName: "hourglass.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(statusTooltipText)
            .popover(isPresented: $isShowingStatusPopover, arrowEdge: .trailing) {
                statusDetailsPopover
            }

            Spacer()
                .frame(width: 10)

            // Account Name, Badges & Info (Width 250)
            VStack(alignment: .leading, spacing: 3) {
                if isEditingName {
                    HStack(spacing: 4) {
                        TextField("Name", text: $editedName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .onSubmit {
                                saveName()
                            }
                        Button("✓") {
                            saveName()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(account.cleanDisplayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // Type Badge (Personal vs Business)
                        AccountTypeBadge(type: account.displayAccountType)

                        // Package Badge (Max, Pro, Ultra, Team)
                        AccountPlanBadge(plan: account.displayPlan)

                        if account.isMock {
                            Text("MOCK")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(3)
                                .fixedSize()
                        }
                    }
                }

                HStack(spacing: 4) {
                    if let email = account.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if account.displayAccountType != "Personal",
                       let org = account.organizationName,
                       !org.isEmpty,
                       org != account.cleanDisplayName {
                        Text("• \(org)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }

                if let errMsg = account.status.errorMessage {
                    Button {
                        isShowingStatusPopover = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text(errMsg)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Click to view error details & re-authenticate")
                }
            }
            .frame(width: 280, alignment: .leading)

            Spacer()

            // 5-Hour Session Quota Column (Width 110)
            VStack(alignment: .leading, spacing: 2) {
                if account.isNeedsAuth && account.usage == nil {
                    Button {
                        store.accountToReauth = account
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                            Text("Reauth")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color(red: 0.85, green: 0.47, blue: 0.34))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Re-authenticate to restore quota tracking")
                } else {
                    CompactQuotaMeter(title: "5-Hour Session", quota: account.usage?.session5h)
                }
            }
            .frame(width: 110, alignment: .leading)

            Spacer()

            // 7-Day Weekly Quota Column (Width 110)
            VStack(alignment: .leading, spacing: 2) {
                CompactQuotaMeter(title: "7-Day Weekly", quota: account.usage?.weekly7d)
            }
            .frame(width: 110, alignment: .leading)

            Spacer()

            // Proxy Column (Width 110)
            Button {
                localProxyEnabled = account.proxy.isEnabled
                localProxyUrl = account.proxy.url
                proxyTestMessage = nil
                proxyTestSuccess = nil
                isShowingProxyPopover = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: account.proxy.isEnabled ? "shield.fill" : "network")
                        .font(.system(size: 12))

                    if account.proxy.isEnabled {
                        Text(shortProxyUrl(account.proxy.url))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    } else {
                        Text("Proxy: Off")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundColor(account.proxy.isEnabled ? .blue : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(account.proxy.isEnabled ? Color.blue.opacity(0.12) : Color.primary.opacity(0.05))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingProxyPopover, arrowEdge: .bottom) {
                proxyConfigPopover
            }
            .frame(width: 110, alignment: .leading)

            Spacer()

            // Actions Column: Reauth, Refresh & Delete (Width 100, 30x30 buttons)
            HStack(spacing: 6) {
                if account.isNeedsAuth {
                    Button {
                        store.accountToReauth = account
                    } label: {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 30, height: 30)
                    .background(Color(red: 0.85, green: 0.47, blue: 0.34))
                    .cornerRadius(6)
                    .help("Re-authenticate account with Claude.ai")
                }

                Button {
                    Task {
                        await store.refreshAccount(id: account.id)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(account.status == .refreshing ? 360 : 0))
                        .animation(account.status == .refreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: account.status)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
                .help("Refresh account limits")

                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
                .help("Remove account")
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .contextMenu {
            if account.isNeedsAuth {
                Button {
                    store.accountToReauth = account
                } label: {
                    Label("Re-authenticate '\(account.cleanDisplayName)'", systemImage: "key.fill")
                }
                Divider()
            }

            Button {
                Task {
                    await store.refreshAccount(id: account.id)
                }
            } label: {
                Label("Refresh Limits", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Label("Remove Account", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Remove '\(account.name)'?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Account", role: .destructive) {
                store.removeAccount(id: account.id)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Status Details Popover

    private var statusDetailsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: account.isNeedsAuth ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundColor(statusColor)
                    .font(.system(size: 13))
                Text(account.status.title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
            }

            if let errorMsg = account.status.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error Details:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Text(errorMsg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }

                Text("The credentials for this account could not retrieve usage limits. Re-authenticating with Claude.ai will issue fresh tokens and restore limit tracking.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if account.isNeedsAuth {
                    Button {
                        isShowingStatusPopover = false
                        store.accountToReauth = account
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                            Text("Re-authenticate")
                        }
                        .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.85, green: 0.47, blue: 0.34))
                    .controlSize(.small)
                }

                if let errorMsg = account.status.errorMessage {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(errorMsg, forType: .string)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Error")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Button("Retry") {
                    isShowingStatusPopover = false
                    Task {
                        await store.refreshAccount(id: account.id)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Proxy Popover

    private var proxyConfigPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Proxy for \(account.name)")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Toggle("", isOn: $localProxyEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Proxy URL:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("http://127.0.0.1:7890", text: $localProxyUrl)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 240)
            }

            if let msg = proxyTestMessage {
                HStack(spacing: 4) {
                    Image(systemName: proxyTestSuccess == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text(msg)
                        .font(.system(size: 10))
                }
                .foregroundColor(proxyTestSuccess == true ? .green : .red)
            }

            HStack {
                Button {
                    testProxy()
                } label: {
                    if isTestingProxy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("Test Ping")
                    }
                }
                .controlSize(.small)
                .disabled(isTestingProxy || localProxyUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("Save") {
                    store.setProxy(for: account.id, isEnabled: localProxyEnabled, url: localProxyUrl)
                    isShowingProxyPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 270)
    }

    private func shortProxyUrl(_ fullUrl: String) -> String {
        var str = fullUrl.replacingOccurrences(of: "http://", with: "")
        str = str.replacingOccurrences(of: "socks5://", with: "")
        str = str.replacingOccurrences(of: "https://", with: "")
        return str.isEmpty ? "Proxy" : str
    }

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.updateAccountName(id: account.id, newName: trimmed)
        }
        isEditingName = false
    }

    private func testProxy() {
        isTestingProxy = true
        proxyTestMessage = nil
        proxyTestSuccess = nil

        let url = localProxyUrl
        Task {
            let res = await ProxySessionManager.shared.testProxy(proxyUrl: url)
            await MainActor.run {
                self.isTestingProxy = false
                self.proxyTestSuccess = res.isSuccess
                if let lat = res.latencyMs {
                    self.proxyTestMessage = "\(res.message) (\(Int(lat))ms)"
                } else {
                    self.proxyTestMessage = res.message
                }
            }
        }
    }
}
