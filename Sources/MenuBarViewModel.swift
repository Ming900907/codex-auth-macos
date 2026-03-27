import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    private enum RefreshTrigger: Equatable {
        case manual
        case automatic
    }

    typealias SleepAction = @Sendable (UInt64) async -> Void

    @Published private(set) var state = AppState.loading
    @Published private(set) var isSwitching = false
    @Published private(set) var isRemoving = false
    @Published private(set) var isLoggingIn = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let loadSnapshotAction: () throws -> AppSnapshot
    private let switchAccountAction: (String) throws -> Void
    private let removeAccountAction: (String) throws -> Void
    private let validateAccountAccessAction: (String) throws -> Void
    private let runLoginAction: () async throws -> Void
    private let cancelLoginAction: () -> Void
    private let autoRefreshIntervalNanoseconds: UInt64
    private let loginRefreshRetryCount: Int
    private let loginRefreshRetryIntervalNanoseconds: UInt64
    private let sleepAction: SleepAction
    private var autoRefreshTask: Task<Void, Never>?
    private var loginTask: Task<Void, Never>?
    private var loginAttemptID: UUID?
    private var clearsStatusMessageAfterNextRefresh = false

    init(
        store: CodexDataStore = CodexDataStore(),
        loginRunner: CodexLoginCommandRunner = CodexLoginCommandRunner(),
        autoRefreshIntervalNanoseconds: UInt64 = 300_000_000_000,
        loginRefreshRetryCount: Int = 6,
        loginRefreshRetryIntervalNanoseconds: UInt64 = 500_000_000,
        sleepAction: @escaping SleepAction = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        loadSnapshotAction = { try store.loadSnapshot() }
        switchAccountAction = { accountKey in try store.switchAccount(accountKey: accountKey) }
        removeAccountAction = { accountKey in try store.removeAccount(accountKey: accountKey) }
        validateAccountAccessAction = { accountKey in try store.validateAccountAccess(accountKey: accountKey) }
        runLoginAction = { try await loginRunner.runLogin() }
        cancelLoginAction = { loginRunner.cancelLogin() }
        self.autoRefreshIntervalNanoseconds = autoRefreshIntervalNanoseconds
        self.loginRefreshRetryCount = loginRefreshRetryCount
        self.loginRefreshRetryIntervalNanoseconds = loginRefreshRetryIntervalNanoseconds
        self.sleepAction = sleepAction
        refresh(trigger: .manual)
        startAutoRefresh()
    }

    init(
        loadSnapshotAction: @escaping () throws -> AppSnapshot,
        switchAccountAction: @escaping (String) throws -> Void,
        removeAccountAction: @escaping (String) throws -> Void,
        validateAccountAccessAction: @escaping (String) throws -> Void,
        runLoginAction: @escaping () async throws -> Void,
        cancelLoginAction: @escaping () -> Void,
        autoRefreshIntervalNanoseconds: UInt64 = 300_000_000_000,
        loginRefreshRetryCount: Int = 6,
        loginRefreshRetryIntervalNanoseconds: UInt64 = 500_000_000,
        sleepAction: @escaping SleepAction = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.loadSnapshotAction = loadSnapshotAction
        self.switchAccountAction = switchAccountAction
        self.removeAccountAction = removeAccountAction
        self.validateAccountAccessAction = validateAccountAccessAction
        self.runLoginAction = runLoginAction
        self.cancelLoginAction = cancelLoginAction
        self.autoRefreshIntervalNanoseconds = autoRefreshIntervalNanoseconds
        self.loginRefreshRetryCount = loginRefreshRetryCount
        self.loginRefreshRetryIntervalNanoseconds = loginRefreshRetryIntervalNanoseconds
        self.sleepAction = sleepAction
        refresh(trigger: .manual)
        startAutoRefresh()
    }

    deinit {
        autoRefreshTask?.cancel()
        loginTask?.cancel()
    }

    var menuBarTitle: String {
        switch state {
        case .loading:
            return "Codex"
        case .loaded(let snapshot):
            return snapshot.activeAccount?.displayName ?? "Codex"
        case .failed:
            return "Codex"
        }
    }

    func refresh() {
        refresh(trigger: .manual)
    }

    private func refresh(trigger: RefreshTrigger) {
        if isSwitching || isRemoving || isLoggingIn {
            return
        }

        let shouldShowRefreshOverlay: Bool
        switch state {
        case .loading:
            shouldShowRefreshOverlay = false
        case .loaded, .failed:
            shouldShowRefreshOverlay = trigger == .manual
        }

        errorMessage = nil
        if case .loaded = state {
            // Keep existing content while refreshing.
        } else if trigger == .manual {
            state = .loading
        }

        isRefreshing = shouldShowRefreshOverlay

        Task {
            defer {
                if shouldShowRefreshOverlay {
                    isRefreshing = false
                }
            }

            do {
                let snapshot = try loadSnapshotAction()
                state = .loaded(snapshot)
                if clearsStatusMessageAfterNextRefresh {
                    statusMessage = nil
                    clearsStatusMessageAfterNextRefresh = false
                }
            } catch {
                state = .failed
                errorMessage = error.localizedDescription
                if clearsStatusMessageAfterNextRefresh {
                    statusMessage = nil
                    clearsStatusMessageAfterNextRefresh = false
                }
            }
        }
    }

    func switchAccount(_ accountKey: String) {
        guard !isSwitching, !isRemoving, !isLoggingIn else { return }
        isSwitching = true
        errorMessage = nil
        statusMessage = nil

        Task {
            defer { isSwitching = false }

            do {
                try switchAccountAction(accountKey)
                let snapshot = try loadSnapshotAction()
                state = .loaded(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeAccount(_ accountKey: String) {
        guard !isSwitching, !isRemoving, !isLoggingIn else { return }
        isRemoving = true
        errorMessage = nil
        statusMessage = nil

        Task {
            defer { isRemoving = false }

            do {
                try removeAccountAction(accountKey)
                let snapshot = try loadSnapshotAction()
                state = .loaded(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func validateAccountAccess(_ accountKey: String) {
        guard !isSwitching, !isRemoving, !isLoggingIn else { return }

        Task {
            do {
                try validateAccountAccessAction(accountKey)
                let snapshot = try loadSnapshotAction()
                state = .loaded(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loginNewAccount() {
        guard !isSwitching, !isRemoving, !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil
        statusMessage = "codex login started. Finish sign-in in the browser."

        let attemptID = UUID()
        loginAttemptID = attemptID
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await runLoginAction()
                guard loginAttemptID == attemptID else { return }
                let baselineAccountKeys = currentAccountKeys()
                isLoggingIn = false
                loginAttemptID = nil
                clearsStatusMessageAfterNextRefresh = true
                statusMessage = "Login finished. Refreshing accounts..."
                await refreshAfterLogin(baselineAccountKeys: baselineAccountKeys)
            } catch {
                guard loginAttemptID == attemptID else { return }
                isLoggingIn = false
                loginAttemptID = nil
                clearsStatusMessageAfterNextRefresh = false
                if let error = error as? CodexLoginError, error == .cancelled {
                    statusMessage = error.localizedDescription
                    errorMessage = nil
                } else {
                    statusMessage = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelLogin() {
        guard isLoggingIn else { return }
        loginAttemptID = nil
        loginTask?.cancel()
        loginTask = nil
        cancelLoginAction()
        isLoggingIn = false
        errorMessage = nil
        clearsStatusMessageAfterNextRefresh = false
        statusMessage = "Login cancelled"
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: autoRefreshIntervalNanoseconds)
                if Task.isCancelled {
                    break
                }
                await MainActor.run {
                    self.refresh(trigger: .automatic)
                }
            }
        }
    }

    private func refreshAfterLogin(baselineAccountKeys: Set<String>) async {
        let attempts = max(1, loginRefreshRetryCount)

        for attempt in 0..<attempts {
            do {
                let snapshot = try loadSnapshotAction()
                state = .loaded(snapshot)

                let refreshedAccountKeys = Set(snapshot.accounts.map(\.accountKey))
                let shouldStop = refreshedAccountKeys != baselineAccountKeys || attempt == attempts - 1
                if shouldStop {
                    if clearsStatusMessageAfterNextRefresh {
                        statusMessage = nil
                        clearsStatusMessageAfterNextRefresh = false
                    }
                    return
                }
            } catch {
                state = .failed
                errorMessage = error.localizedDescription
                if clearsStatusMessageAfterNextRefresh {
                    statusMessage = nil
                    clearsStatusMessageAfterNextRefresh = false
                }
                return
            }

            await sleepAction(loginRefreshRetryIntervalNanoseconds)
        }
    }

    private func currentAccountKeys() -> Set<String> {
        guard case .loaded(let snapshot) = state else {
            return []
        }
        return Set(snapshot.accounts.map(\.accountKey))
    }
}

enum AppState {
    case loading
    case loaded(AppSnapshot)
    case failed
}
