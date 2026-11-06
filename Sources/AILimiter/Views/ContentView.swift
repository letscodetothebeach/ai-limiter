import SwiftUI
import UniformTypeIdentifiers

struct AccountRowDropDelegate: DropDelegate {
    let targetAccount: Account
    let store: AccountStore
    @Binding var draggedAccount: Account?

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedAccount,
              dragged.id != targetAccount.id,
              let fromIndex = store.accounts.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = store.accounts.firstIndex(where: { $0.id == targetAccount.id }) else { return }

        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.2)) {
                store.moveAccounts(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAccount = nil
        return true
    }
}

public struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @State private var isShowingAddSheet: Bool = false
    @State private var searchText: String = ""
    @State private var draggedAccount: Account? = nil

    public init() {}

    private var filteredAccounts: [Account] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.accounts
        }
        let q = searchText.lowercased()
        return store.accounts.filter {
            $0.name.lowercased().contains(q) ||
            ($0.email?.lowercased().contains(q) ?? false) ||
            ($0.organizationName?.lowercased().contains(q) ?? false)
        }
    }

    private var maxSessionUtilization: Double {
        store.accounts.compactMap { $0.usage?.session5h?.utilization }.max() ?? 0
    }

    private var mockCount: Int {
        store.accounts.filter { $0.isMock }.count
    }

    private var accountsWithProxyCount: Int {
        store.accounts.filter { $0.proxy.isEnabled }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Top Navigation & Action Bar
            topBar

            Divider()

            if store.accounts.isEmpty {
                emptyStateView
            } else {
                // Table Column Headers
                columnHeaders
                Divider()

                // High-density drag-and-drop accounts list
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(filteredAccounts.enumerated()), id: \.element.id) { index, account in
                            AccountRowView(account: account, index: index)
                                .onDrag {
                                    draggedAccount = account
                                    return NSItemProvider(object: account.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: AccountRowDropDelegate(
                                    targetAccount: account,
                                    store: store,
                                    draggedAccount: $draggedAccount
                                ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }

            Divider()

            // Bottom Status Bar
            bottomStatusBar
        }
        .frame(minWidth: 840, minHeight: 520)
        .sheet(isPresented: $isShowingAddSheet) {
            AddAccountSheet()
                .environmentObject(store)
        }
    }

    // MARK: - Top Toolbar

    private var topBar: some View {
        HStack(spacing: 14) {
            // App Branding & Title: "AI Limiter"
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.85, green: 0.47, blue: 0.34))
                        .frame(width: 30, height: 30)

                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("AI Limiter")
                            .font(.system(size: 14, weight: .bold))

                        Text("\(store.accounts.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(10)
                    }
                }
            }

            Spacer()

            // Search filter
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 120)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)

            // Auto-refresh control (with persistent state!)
            HStack(spacing: 6) {
                Toggle(isOn: $store.autoRefreshEnabled) {
                    Text("Auto")
                        .font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .help("Automatically refreshes limits periodically")

                if store.autoRefreshEnabled {
                    Picker("", selection: $store.autoRefreshIntervalSeconds) {
                        Text("1m").tag(TimeInterval(60))
                        Text("5m").tag(TimeInterval(300))
                        Text("15m").tag(TimeInterval(900))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 65)
                    .controlSize(.small)
                }
            }

            // Refresh All Button
            Button {
                Task {
                    await store.refreshAllAccounts()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isRefreshingAll ? 360 : 0))
                        .animation(store.isRefreshingAll ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshingAll)
                    Text("Refresh All")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isRefreshingAll || store.accounts.isEmpty)

            // Primary Connect Button
            Button {
                isShowingAddSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("Connect Account")
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.85, green: 0.47, blue: 0.34))
            .controlSize(.small)

            // Secondary Menu
            Menu {
                if mockCount > 0 {
                    Button(role: .destructive) {
                        store.clearAllMockAccounts()
                    } label: {
                        Label("Remove All Mock Accounts (\(mockCount))", systemImage: "trash")
                    }
                    Divider()
                }

                Button {
                    isShowingAddSheet = true
                } label: {
                    Label("Add Account Options...", systemImage: "slider.horizontal.3")
                }

                Button {
                    store.clearAllAccounts()
                } label: {
                    Label("Clear All Accounts", systemImage: "trash.slash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .frame(width: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("#")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)

            Circle()
                .fill(Color.clear)
                .frame(width: 8, height: 8)

            Text("ACCOUNT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 220, alignment: .leading)

            Spacer()

            Text("5-HOUR LIMIT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Spacer()

            Text("7-DAY LIMIT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Spacer()

            Text("PROXY")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            Spacer()

            Text("ACTIONS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.12))
                    .frame(width: 76, height: 76)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 34))
                    .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
            }

            VStack(spacing: 5) {
                Text("No Accounts Connected")
                    .font(.system(size: 17, weight: .bold))
                Text("Connect your account to monitor 5-Hour session limits and 7-Day weekly quotas in real-time.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                isShowingAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                    Text("Connect Account (OAuth)")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.85, green: 0.47, blue: 0.34))
            .controlSize(.regular)
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Bottom Status Bar

    private var bottomStatusBar: some View {
        HStack {
            if let last = store.lastGlobalRefresh {
                Text("Updated \(formattedDate(last))")
            } else {
                Text("Ready")
            }

            Spacer()

            if accountsWithProxyCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 9))
                    Text("\(accountsWithProxyCount) proxy active")
                }
                .foregroundColor(.blue)
            }

            Text("•")
                .foregroundColor(.secondary.opacity(0.4))

            Text("Drag rows to rearrange order")
                .foregroundColor(.secondary.opacity(0.8))
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
