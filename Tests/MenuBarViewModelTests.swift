import Foundation
import Testing
@testable import CodexAuthMacOSBar

@MainActor
struct MenuBarViewModelTests {
    @Test
    func loginSuccessClearsRefreshingStatusAfterRefreshCompletes() async {
        let snapshot = makeSnapshot(accountKeys: ["user-a::acct-a"], activeAccountKey: "user-a::acct-a")
        var loadSnapshotCallCount = 0
        let viewModel = MenuBarViewModel(
            loadSnapshotAction: {
                loadSnapshotCallCount += 1
                return snapshot
            },
            switchAccountAction: { _ in },
            removeAccountAction: { _ in },
            validateAccountAccessAction: { _ in },
            runLoginAction: { () async throws in },
            cancelLoginAction: {},
            autoRefreshIntervalNanoseconds: 3_600_000_000_000,
            loginRefreshRetryCount: 1,
            loginRefreshRetryIntervalNanoseconds: 0,
            sleepAction: { _ in }
        )

        await waitUntil { if case .loaded = viewModel.state { true } else { false } }

        viewModel.loginNewAccount()

        await waitUntil { !viewModel.isLoggingIn }
        await waitUntil { viewModel.statusMessage == nil }

        #expect(viewModel.errorMessage == nil)
        #expect(loadSnapshotCallCount >= 2)

        switch viewModel.state {
        case .loaded(let loadedSnapshot):
            #expect(loadedSnapshot.activeAccount?.accountKey == "user-a::acct-a")
        case .loading, .failed:
            Issue.record("expected loaded state after login refresh")
        }
    }

    @Test
    func loginSuccessRetriesUntilNewAccountAppears() async {
        let originalSnapshot = makeSnapshot(accountKeys: ["user-a::acct-a"], activeAccountKey: "user-a::acct-a")
        let updatedSnapshot = makeSnapshot(
            accountKeys: ["user-a::acct-a", "user-b::acct-b"],
            activeAccountKey: "user-a::acct-a"
        )
        var loadSnapshotCallCount = 0
        let viewModel = MenuBarViewModel(
            loadSnapshotAction: {
                defer { loadSnapshotCallCount += 1 }
                switch loadSnapshotCallCount {
                case 0, 1:
                    return originalSnapshot
                default:
                    return updatedSnapshot
                }
            },
            switchAccountAction: { _ in },
            removeAccountAction: { _ in },
            validateAccountAccessAction: { _ in },
            runLoginAction: { () async throws in },
            cancelLoginAction: {},
            autoRefreshIntervalNanoseconds: 3_600_000_000_000,
            loginRefreshRetryCount: 3,
            loginRefreshRetryIntervalNanoseconds: 0,
            sleepAction: { _ in }
        )

        await waitUntil { if case .loaded = viewModel.state { true } else { false } }

        viewModel.loginNewAccount()

        await waitUntil { !viewModel.isLoggingIn }
        await waitUntil {
            if case .loaded(let snapshot) = viewModel.state {
                return snapshot.accounts.count == 2
            }
            return false
        }
        await waitUntil { viewModel.statusMessage == nil }

        #expect(loadSnapshotCallCount >= 3)

        switch viewModel.state {
        case .loaded(let loadedSnapshot):
            #expect(Set(loadedSnapshot.accounts.map { $0.accountKey }) == Set(["user-a::acct-a", "user-b::acct-b"]))
        case .loading, .failed:
            Issue.record("expected updated account list after login retry")
        }
    }

    @Test
    func manualRefreshShowsLoadingOverlayUntilSnapshotArrives() async {
        let snapshot = makeSnapshot(accountKeys: ["user-a::acct-a"], activeAccountKey: "user-a::acct-a")
        var loadSnapshotCallCount = 0
        let viewModel = MenuBarViewModel(
            loadSnapshotAction: {
                defer { loadSnapshotCallCount += 1 }
                if loadSnapshotCallCount >= 1 {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                return snapshot
            },
            switchAccountAction: { _ in },
            removeAccountAction: { _ in },
            validateAccountAccessAction: { _ in },
            runLoginAction: { () async throws in },
            cancelLoginAction: {},
            autoRefreshIntervalNanoseconds: 3_600_000_000_000,
            loginRefreshRetryCount: 1,
            loginRefreshRetryIntervalNanoseconds: 0,
            sleepAction: { _ in }
        )

        await waitUntil { if case .loaded = viewModel.state { true } else { false } }

        viewModel.refresh()

        await waitUntil { viewModel.isRefreshing }
        await waitUntil { !viewModel.isRefreshing }

        #expect(loadSnapshotCallCount >= 2)

        switch viewModel.state {
        case .loaded(let loadedSnapshot):
            #expect(loadedSnapshot.activeAccount?.accountKey == "user-a::acct-a")
        case .loading, .failed:
            Issue.record("expected loaded state after manual refresh")
        }
    }

    @Test
    func removeAccountRefreshesSnapshotAfterDeletion() async {
        let initialSnapshot = makeSnapshot(
            accountKeys: ["user-a::acct-a", "user-b::acct-b"],
            activeAccountKey: "user-a::acct-a"
        )
        let updatedSnapshot = makeSnapshot(accountKeys: ["user-a::acct-a"], activeAccountKey: "user-a::acct-a")
        var loadSnapshotCallCount = 0
        var removedAccountKey: String?

        let viewModel = MenuBarViewModel(
            loadSnapshotAction: {
                defer { loadSnapshotCallCount += 1 }
                return loadSnapshotCallCount == 0 ? initialSnapshot : updatedSnapshot
            },
            switchAccountAction: { _ in },
            removeAccountAction: { accountKey in
                removedAccountKey = accountKey
            },
            validateAccountAccessAction: { _ in },
            runLoginAction: { () async throws in },
            cancelLoginAction: {},
            autoRefreshIntervalNanoseconds: 3_600_000_000_000,
            loginRefreshRetryCount: 1,
            loginRefreshRetryIntervalNanoseconds: 0,
            sleepAction: { _ in }
        )

        await waitUntil { if case .loaded = viewModel.state { true } else { false } }

        viewModel.removeAccount("user-b::acct-b")

        await waitUntil { !viewModel.isRemoving }
        await waitUntil {
            if case .loaded(let snapshot) = viewModel.state {
                return snapshot.accounts.count == 1
            }
            return false
        }

        #expect(removedAccountKey == "user-b::acct-b")
        #expect(loadSnapshotCallCount >= 2)
    }

    @Test
    func validateInactiveAccountAccessRefreshesSnapshot() async {
        let initialSnapshot = makeSnapshot(
            accountKeys: ["user-a::acct-a", "user-b::acct-b"],
            activeAccountKey: "user-a::acct-a"
        )
        let validatedSnapshot = AppSnapshot(
            accounts: [
                AccountSummary(
                    id: "user-a::acct-a",
                    accountKey: "user-a::acct-a",
                    email: "user0@example.com",
                    alias: "",
                    plan: "plus",
                    isActive: true,
                    usage: nil,
                    accessIssue: nil
                ),
                AccountSummary(
                    id: "user-b::acct-b",
                    accountKey: "user-b::acct-b",
                    email: "user1@example.com",
                    alias: "",
                    plan: "team",
                    isActive: false,
                    usage: nil,
                    accessIssue: "Account access invalid. Re-login required."
                )
            ],
            activeAccount: AccountSummary(
                id: "user-a::acct-a",
                accountKey: "user-a::acct-a",
                email: "user0@example.com",
                alias: "",
                plan: "plus",
                isActive: true,
                usage: nil,
                accessIssue: nil
            ),
            usage: nil,
            activeAccessIssue: nil
        )
        var loadSnapshotCallCount = 0
        var validatedAccountKey: String?

        let viewModel = MenuBarViewModel(
            loadSnapshotAction: {
                defer { loadSnapshotCallCount += 1 }
                return loadSnapshotCallCount == 0 ? initialSnapshot : validatedSnapshot
            },
            switchAccountAction: { _ in },
            removeAccountAction: { _ in },
            validateAccountAccessAction: { accountKey in
                validatedAccountKey = accountKey
            },
            runLoginAction: { () async throws in },
            cancelLoginAction: {},
            autoRefreshIntervalNanoseconds: 3_600_000_000_000,
            loginRefreshRetryCount: 1,
            loginRefreshRetryIntervalNanoseconds: 0,
            sleepAction: { _ in }
        )

        await waitUntil { if case .loaded = viewModel.state { true } else { false } }

        viewModel.validateAccountAccess("user-b::acct-b")

        await waitUntil {
            if case .loaded(let snapshot) = viewModel.state {
                return snapshot.accounts.first(where: { $0.accountKey == "user-b::acct-b" })?.isAccessInvalid == true
            }
            return false
        }

        #expect(validatedAccountKey == "user-b::acct-b")
        #expect(loadSnapshotCallCount >= 2)
    }

    @Test
    func validateInactiveAccountAccessSkipsAlreadyInvalidAccount() async {
        let invalidSnapshot = AppSnapshot(
            accounts: [
                AccountSummary(
                    id: "user-a::acct-a",
                    accountKey: "user-a::acct-a",
                    email: "user0@example.com",
                    alias: "",
                    plan: "plus",
                    isActive: true,
                    usage: nil,
                    accessIssue: nil
                ),
                AccountSummary(
                    id: "user-b::acct-b",
                    accountKey: "user-b::acct-b",
                    email: "user1@example.com",
                    alias: "",
                    plan: "team",
                    isActive: false,
                    usage: nil,
                    accessIssue: "Account access invalid. Re-login required."
                )
            ],
            activeAccount: AccountSummary(
                id: "user-a::acct-a",
                accountKey: "user-a::acct-a",
                email: "user0@example.com",
                alias: "",
                plan: "plus",
                isActive: true,
                usage: nil,
                accessIssue: nil
            ),
            usage: nil,
            activeAccessIssue: nil
        )
        var validateCallCount = 0

        let viewModel = MenuBarViewModel(
            loadSnapshotAction: { invalidSnapshot },
            switchAccountAction: { _ in },
            removeAccountAction: { _ in },
            validateAccountAccessAction: {
                validateCallCount += 1
            },
            runLoginAction: { () async throws in },
            cancelLoginAction: {},
            autoRefreshIntervalNanoseconds: 3_600_000_000_000,
            loginRefreshRetryCount: 1,
            loginRefreshRetryIntervalNanoseconds: 0,
            sleepAction: { _ in }
        )

        await waitUntil { if case .loaded = viewModel.state { true } else { false } }

        viewModel.validateAccountAccess("user-b::acct-b")

        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(validateCallCount == 0)
    }
}

private func makeSnapshot(accountKeys: [String], activeAccountKey: String) -> AppSnapshot {
    let accounts = accountKeys.enumerated().map { index, accountKey in
        AccountSummary(
            id: accountKey,
            accountKey: accountKey,
            email: "user\(index)@example.com",
            alias: "",
            plan: index == 0 ? "plus" : "team",
            isActive: accountKey == activeAccountKey,
            usage: nil,
            accessIssue: nil
        )
    }

    return AppSnapshot(
        accounts: accounts,
        activeAccount: accounts.first(where: { $0.accountKey == activeAccountKey }),
        usage: nil,
        activeAccessIssue: nil
    )
}

@MainActor
private func waitUntil(
    attempts: Int = 100,
    sleepNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<attempts {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: sleepNanoseconds)
    }

    Issue.record("condition was not met before timeout")
}
