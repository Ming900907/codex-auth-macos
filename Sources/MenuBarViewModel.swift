import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    private enum RefreshTrigger: Equatable {
        case manual
        case automatic
    }

    @Published private(set) var state = AppState.loading
    @Published private(set) var isSwitching = false
    @Published private(set) var errorMessage: String?

    private let store: CodexDataStore
    private let autoRefreshIntervalNanoseconds: UInt64
    private var autoRefreshTask: Task<Void, Never>?

    init(
        store: CodexDataStore = CodexDataStore(),
        autoRefreshIntervalNanoseconds: UInt64 = 300_000_000_000
    ) {
        self.store = store
        self.autoRefreshIntervalNanoseconds = autoRefreshIntervalNanoseconds
        refresh(trigger: .manual)
        startAutoRefresh()
    }

    deinit {
        autoRefreshTask?.cancel()
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
        if isSwitching {
            return
        }

        errorMessage = nil
        if case .loaded = state {
            // Keep existing content while refreshing.
        } else if trigger == .manual {
            state = .loading
        } else {
            // Keep current state during background refresh.
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
        guard !isSwitching else { return }
        isSwitching = true
        errorMessage = nil

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
