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

// Helper to ensure window does not auto-focus search field on launch
// and unfocuses when clicking outside
struct WindowFocusHelper: NSViewRepresentable {
    var onUnfocus: () -> Void

    func makeNSView(context: Context) -> FocusDummyNSView {
        let view = FocusDummyNSView()
        view.onResignFocus = onUnfocus
        return view
    }

    func updateNSView(_ nsView: FocusDummyNSView, context: Context) {
        nsView.onResignFocus = onUnfocus
    }

    @MainActor
    final class FocusDummyNSView: NSView {
        var onResignFocus: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }
            // Prevent search text field from being the automatic initial first responder
            window.initialFirstResponder = self
            DispatchQueue.main.async {
                window.makeFirstResponder(nil)
            }

            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    guard let self = self, let win = self.window else { return event }
                    if let firstResponder = win.firstResponder as? NSView,
                       firstResponder is NSTextView || firstResponder is NSTextField {
                        let locationInWindow = event.locationInWindow
                        let hitView = win.contentView?.hitTest(locationInWindow)
                        if hitView != firstResponder && !(hitView?.isDescendant(of: firstResponder) ?? false) {
                            win.makeFirstResponder(nil)
                            self.onResignFocus?()
                        }
                    }
                    return event
                }
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
    }
}

public struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @State private var isShowingAddSheet: Bool = false
    @State private var searchText: String = ""
    @State private var draggedAccount: Account? = nil
    @FocusState private var isSearchFocused: Bool

    public init() {}

    private var filteredAccounts: [Account] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.accounts
        }
        let q = searchText.lowercased()
        return store.accounts.filter {
            $0.name.lowercased().contains(q) ||
            ($0.email?.lowercased().contains(q) ?? false) ||
            ($0.organizationName?.lowercased().contains(q) ?? false) ||
            ($0.note?.lowercased().contains(q) ?? false)
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
        .frame(minWidth: 980, minHeight: 520)
        .background(WindowFocusHelper {
            isSearchFocused = false
        })
        .onAppear {
            isSearchFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddAccountSheet()
                .environmentObject(store)
        }
        .sheet(item: $store.accountToReauth) { account in
            ReauthSheet(account: account)
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
                        .frame(width: 32, height: 32)

                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("AI Limiter")
                            .font(.system(size: 15, weight: .bold))

                        Text("\(store.accounts.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(10)
                    }
                }
            }

            Spacer()

            // Search filter with clear unfocus capability
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)
                    .frame(width: 130)
                    .onExitCommand {
                        isSearchFocused = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    .onSubmit {
                        isSearchFocused = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFocused = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(isSearchFocused ? 0.25 : 0.08), lineWidth: 1)
            )

            // Auto-refresh control (with persistent state!)
            HStack(spacing: 8) {
                Toggle(isOn: $store.autoRefreshEnabled) {
                    Text("Auto")
                        .font(.system(size: 12, weight: .medium))
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
                    .frame(width: 72)
                    .controlSize(.regular)
                }
            }

            // Refresh All Button
            Button {
                Task {
                    await store.refreshAllAccounts()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(store.isRefreshingAll ? 360 : 0))
                        .animation(store.isRefreshingAll ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshingAll)
                    Text("Refresh All")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(store.isRefreshingAll || store.accounts.isEmpty)

            // Primary Connect Button
            Button {
                isShowingAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Connect Account")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.85, green: 0.47, blue: 0.34))
            .controlSize(.regular)

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
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderedButton)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("#")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)

            Circle()
                .fill(Color.clear)
                .frame(width: 16, height: 16)

            Spacer()
                .frame(width: 10)

            Text("ACCOUNT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 320, alignment: .leading)

            Spacer()

            Text("PROJECT / NOTE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 190, alignment: .leading)

            Spacer()

            Text("5-HOUR LIMIT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 115, alignment: .leading)

            Spacer()

            Text("7-DAY LIMIT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 115, alignment: .leading)

            Spacer()

            Text("ACTIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 95, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 7)
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
