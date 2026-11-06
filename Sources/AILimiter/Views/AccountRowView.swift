import SwiftUI

public struct AccountRowView: View {
    @EnvironmentObject var store: AccountStore
    public let account: Account
    public let index: Int

    @State private var isEditingName: Bool = false
    @State private var editedName: String = ""
    @State private var isShowingDeleteConfirmation: Bool = false
    @State private var isShowingProxyPopover: Bool = false

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

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Drag Handle & Row Index (1, 2, 3...)
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .help("Drag to reorder")

                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 20)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
            }
            .frame(width: 44, alignment: .leading)

            // Status Dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .help("Status: \(account.status.title)")

            // Account Name & Info (Width ~200-240)
            VStack(alignment: .leading, spacing: 2) {
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(account.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if account.isMock {
                            Text("MOCK")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                }

                HStack(spacing: 4) {
                    if let email = account.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let org = account.organizationName, !org.isEmpty {
                        Text(org)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(account.status.title)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 220, alignment: .leading)

            Spacer()

            // 5-Hour Session Quota Column (Width ~120)
            VStack(alignment: .leading, spacing: 2) {
                CompactQuotaMeter(title: "5-Hour Session", quota: account.usage?.session5h)
            }
            .frame(width: 120, alignment: .leading)

            Spacer()

            // 7-Day Weekly Quota Column (Width ~120)
            VStack(alignment: .leading, spacing: 2) {
                CompactQuotaMeter(title: "7-Day Weekly", quota: account.usage?.weekly7d)
            }
            .frame(width: 120, alignment: .leading)

            Spacer()

            // Proxy Column (Width ~140)
            Button {
                localProxyEnabled = account.proxy.isEnabled
                localProxyUrl = account.proxy.url
                proxyTestMessage = nil
                proxyTestSuccess = nil
                isShowingProxyPopover = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: account.proxy.isEnabled ? "shield.fill" : "network")
                        .font(.system(size: 10))

                    if account.proxy.isEnabled {
                        Text(shortProxyUrl(account.proxy.url))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    } else {
                        Text("Proxy: Off")
                            .font(.system(size: 11))
                    }
                }
                .foregroundColor(account.proxy.isEnabled ? .blue : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(account.proxy.isEnabled ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingProxyPopover, arrowEdge: .bottom) {
                proxyConfigPopover
            }
            .frame(width: 140, alignment: .leading)

            Spacer()

            // Actions Column: Refresh & Delete (Width ~65)
            HStack(spacing: 6) {
                Button {
                    Task {
                        await store.refreshAccount(id: account.id)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(account.status == .refreshing ? 360 : 0))
                        .animation(account.status == .refreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: account.status)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
                .help("Refresh account limits")

                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .background(Color.red.opacity(0.06))
                .cornerRadius(4)
                .help("Remove account")
            }
            .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
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
