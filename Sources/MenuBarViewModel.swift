import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    private enum RefreshTrigger: Equatable {
        case manual
        case automatic
    }

    @Published private(set) var state = AppState.loading
    @Published private(set) var isSwitching = false
    @Published private(set) var isLoggingIn = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let store: CodexDataStore
    private let loginRunner: CodexLoginCommandRunner
    private let autoRefreshIntervalNanoseconds: UInt64
    private var autoRefreshTask: Task<Void, Never>?
    private var loginTask: Task<Void, Never>?
    private var loginAttemptID: UUID?

    init(
        store: CodexDataStore = CodexDataStore(),
        loginRunner: CodexLoginCommandRunner = CodexLoginCommandRunner(),
        autoRefreshIntervalNanoseconds: UInt64 = 300_000_000_000
    ) {
        self.store = store
        self.loginRunner = loginRunner
        self.autoRefreshIntervalNanoseconds = autoRefreshIntervalNanoseconds
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
        if isSwitching || isLoggingIn {
            return
        }

        errorMessage = nil
        if case .loaded = state {
            // Keep existing content while refreshing.
        } else if trigger == .manual {
            state = .loading
        }

        Task {
            do {
                let snapshot = try store.loadSnapshot()
                state = .loaded(snapshot)
            } catch {
                state = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    func switchAccount(_ accountKey: String) {
        guard !isSwitching, !isLoggingIn else { return }
        isSwitching = true
        errorMessage = nil
        statusMessage = nil

        Task {
            defer { isSwitching = false }

            do {
                try store.switchAccount(accountKey: accountKey)
                let snapshot = try store.loadSnapshot()
                state = .loaded(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loginNewAccount() {
        guard !isSwitching, !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil
        statusMessage = "已启动 codex login，请在浏览器完成登录"

        let attemptID = UUID()
        loginAttemptID = attemptID
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await loginRunner.runLogin()
                guard loginAttemptID == attemptID else { return }
                isLoggingIn = false
                loginAttemptID = nil
                statusMessage = "登录完成，正在刷新账号列表"
                refresh(trigger: .manual)
            } catch {
                guard loginAttemptID == attemptID else { return }
                isLoggingIn = false
                loginAttemptID = nil
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
        loginRunner.cancelLogin()
        isLoggingIn = false
        errorMessage = nil
        statusMessage = "已取消登录"
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
}

enum AppState {
    case loading
    case loaded(AppSnapshot)
    case failed
}
