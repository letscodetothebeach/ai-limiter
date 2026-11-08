import SwiftUI

public struct AccountCardView: View {
    @EnvironmentObject var store: AccountStore
    public let account: Account

    @State private var isEditingName: Bool = false
    @State private var editedName: String = ""
    @State private var isShowingDeleteConfirmation: Bool = false
    @State private var isProxySettingsExpanded: Bool = false

    // Local proxy state for editing
    @State private var localProxyEnabled: Bool = false
    @State private var localProxyUrl: String = ""
    @State private var isTestingProxy: Bool = false
    @State private var proxyTestMessage: String? = nil
    @State private var proxyTestSuccess: Bool? = nil

    public init(account: Account) {
        self.account = account
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Name, Badges, Status, and Top Actions
            HStack(alignment: .center, spacing: 12) {
                // Brand / Account Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.18))
                        .frame(width: 42, height: 42)

                    Image(systemName: account.isMock ? "sparkles" : "brain.head.profile")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
                }

                VStack(alignment: .leading, spacing: 3) {
                    if isEditingName {
                        HStack(spacing: 6) {
                            TextField("Account Name", text: $editedName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)
                                .onSubmit {
                                    saveName()
                                }

                            Button("Save") {
                                saveName()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Cancel") {
                                isEditingName = false
                            }
                            .controlSize(.small)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(account.cleanDisplayName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)

                            AccountTypeBadge(type: account.displayAccountType)
                            AccountPlanBadge(plan: account.displayPlan)

                            Button {
                                editedName = account.cleanDisplayName
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Rename account")

                            if account.isMock {
                                Text("MOCK")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.15))
                                    .cornerRadius(4)
                            }

                            if account.proxy.isEnabled {
                                HStack(spacing: 3) {
                                    Image(systemName: "shield.fill")
                                        .font(.system(size: 9))
                                    Text("PROXY")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(4)
                            }
                        }
                    }

                    // Email and Org info
                    HStack(spacing: 8) {
                        if let email = account.email, !email.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 10))
                                Text(email)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.secondary)
                        }

                        if let org = account.organizationName, !org.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.5))
                            HStack(spacing: 4) {
                                Image(systemName: "building.2")
                                    .font(.system(size: 10))
                                Text(org)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Status Badge & Action Buttons
                statusBadge

                // Refresh Button
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
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(account.status == .refreshing)
                .help("Refresh this account's limits")

                // Delete Button
                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Remove account")
            }

            Divider()

            // Main Quota Display
            if let usage = account.usage {
                VStack(spacing: 12) {
                    if let s5 = usage.session5h {
                        QuotaBarView(quota: s5)
                    }

                    if let w7 = usage.weekly7d {
                        QuotaBarView(quota: w7)
                    }

                    // Model quotas if available
                    if !usage.modelQuotas.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MODEL BREAKDOWN")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)

                            ForEach(usage.modelQuotas) { mq in
                                QuotaBarView(quota: mq)
                            }
                        }
                    }

                    if let extra = usage.extraUsage {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 11))
                            Text("Extra Usage: \(extra)")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                        }
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("No usage data yet. Click Refresh to query limits.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Proxy Setting Controls (built into the card)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { account.proxy.isEnabled },
                        set: { newValue in
                            store.setProxy(for: account.id, isEnabled: newValue, url: account.proxy.url)
                            localProxyEnabled = newValue
                        }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: account.proxy.isEnabled ? "network" : "network.slash")
                                .font(.system(size: 12))
                                .foregroundColor(account.proxy.isEnabled ? .blue : .secondary)
                            Text("Route tracking requests via proxy")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        withAnimation {
                            isProxySettingsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isProxySettingsExpanded ? "Hide Settings" : "Configure Proxy")
                                .font(.system(size: 11))
                            Image(systemName: isProxySettingsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                if isProxySettingsExpanded || account.proxy.isEnabled {
                    HStack(spacing: 8) {
                        TextField("http://127.0.0.1:7890 or socks5://127.0.0.1:1080", text: $localProxyUrl)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit {
                                saveProxy()
                            }

                        Button("Apply") {
                            saveProxy()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            testCurrentProxy()
                        } label: {
                            if isTestingProxy {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Text("Test")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isTestingProxy || localProxyUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let message = proxyTestMessage {
                        HStack(spacing: 5) {
                            Image(systemName: proxyTestSuccess == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                            Text(message)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(proxyTestSuccess == true ? .green : .red)
                        .padding(.top, 2)
                    }
                }
            }

            // Footer info
            HStack {
                if let lastUpdated = account.lastUpdated {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("Updated \(timeAgo(since: lastUpdated))")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                if let plan = account.usage?.plan {
                    Text(plan)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            localProxyEnabled = account.proxy.isEnabled
            localProxyUrl = account.proxy.url
        }
        .confirmationDialog(
            "Remove Account",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove '\(account.name)'", role: .destructive) {
                store.removeAccount(id: account.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove this account? You will need to re-authenticate or re-add it to track it again.")
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(account.status.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12))
        .cornerRadius(6)
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

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.updateAccountName(id: account.id, newName: trimmed)
        }
        isEditingName = false
    }

    private func saveProxy() {
        store.setProxy(for: account.id, isEnabled: localProxyEnabled, url: localProxyUrl)
        proxyTestMessage = "Proxy settings saved."
        proxyTestSuccess = true
    }

    private func testCurrentProxy() {
        isTestingProxy = true
        proxyTestMessage = nil
        proxyTestSuccess = nil

        let urlToTest = localProxyUrl

        Task {
            let result = await ProxySessionManager.shared.testProxy(proxyUrl: urlToTest)
            await MainActor.run {
                self.isTestingProxy = false
                self.proxyTestSuccess = result.isSuccess
                if let lat = result.latencyMs {
                    self.proxyTestMessage = "\(result.message) (\(String(format: "%.0f", lat))ms)"
                } else {
                    self.proxyTestMessage = result.message
                }
            }
        }
    }

    private func timeAgo(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
