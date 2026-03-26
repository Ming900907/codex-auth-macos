import Foundation
import Testing
@testable import CodexAuthMacOSBar

struct CodexDataStoreTests {
    @Test
    func loadSnapshotReadsActiveAccountAndUsage() throws {
        let fixture = try Fixture.make()
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        let snapshot = try store.loadSnapshot()

        #expect(snapshot.accounts.count == 2)
        #expect(snapshot.activeAccount?.accountKey == "user-a::acct-a")
        #expect(snapshot.activeAccount?.displayName == "main@example.com")
        #expect(snapshot.usage?.primary?.remainingPercent == 73)
        #expect(snapshot.usage?.secondary?.remainingPercent == 89)
    }

    @Test
    func loadSnapshotIncludesInactiveAccountUsageHistory() throws {
        let fixture = try Fixture.make(registryData: Fixture.registryDataWithStoredUsage)
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        let snapshot = try store.loadSnapshot()
        let inactiveAccount = try #require(snapshot.accounts.first(where: { !$0.isActive }))

        #expect(inactiveAccount.usage?.primary?.remainingPercent == 77)
        #expect(inactiveAccount.usage?.secondary?.remainingPercent == 95)
    }

    @Test
    func switchAccountReplacesAuthAndUpdatesRegistry() throws {
        let fixture = try Fixture.make()
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        try store.switchAccount(accountKey: "user-b::acct-b")

        let authContent = try String(contentsOf: fixture.paths.authFile, encoding: .utf8)
        #expect(authContent.contains("\"account_id\":\"acct-b\""))

        let registry = try store.loadRegistry()
        #expect(registry.activeAccountKey == "user-b::acct-b")
        #expect(registry.accounts.first(where: { $0.accountKey == "user-b::acct-b" })?.lastUsedAt != nil)
    }

    @Test
    func accountAuthFileMatchesRealFilenameStyleWithoutPadding() {
        let paths = CodexPaths(root: URL(fileURLWithPath: "/tmp/codex-test", isDirectory: true))

        let fileName = paths.accountAuthFile(accountKey: "user-a::acct-a").lastPathComponent

        #expect(fileName == "dXNlci1hOjphY2N0LWE.auth.json")
    }

    @Test
    func loadLatestUsageReturnsNilWithoutTokenCount() throws {
        let fixture = try Fixture.make(includeUsage: false)
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        #expect(try store.loadLatestUsage() == nil)
    }

    @Test
    func loadLatestUsageReadsNestedInfoRateLimits() throws {
        let fixture = try Fixture.make(sessionData: Fixture.nestedInfoSessionData)
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        let usage = try store.loadLatestUsage()

        #expect(usage?.primary?.remainingPercent == 64)
        #expect(usage?.secondary?.remainingPercent == 93)
    }

    @Test
    func usageResetTextIncludesDate() {
        let usage = UsageWindow(
            usedPercent: 27,
            remainingPercent: 73,
            resetAt: Date(timeIntervalSince1970: 1774435835)
        )

        #expect(usage.resetText.hasPrefix("Resets "))
        #expect(usage.resetText.contains("03/25"))
        #expect(usage.resetText.contains(":"))
    }

    @Test
    func loadSnapshotCachesLatestUsageIntoActiveAccount() throws {
        let fixture = try Fixture.make()
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        let snapshot = try store.loadSnapshot()
        let registry = try store.loadRegistry()
        let account = try #require(registry.accounts.first(where: { $0.accountKey == "user-a::acct-a" }))

        #expect(snapshot.usage?.primary?.remainingPercent == 73)
        #expect(account.lastUsage?.primary?.usedPercent == 27)
        #expect(account.lastUsage?.secondary?.usedPercent == 11)
        #expect(account.lastUsageAt != nil)
    }

    @Test
    func loadSnapshotFallsBackToAccountHistoryWhenNoNewSessionUsage() throws {
        let fixture = try Fixture.make(includeUsage: false, registryData: Fixture.registryDataWithStoredUsage)
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        let snapshot = try store.loadSnapshot()

        #expect(snapshot.activeAccount?.accountKey == "user-a::acct-a")
        #expect(snapshot.usage?.primary?.remainingPercent == 58)
        #expect(snapshot.usage?.secondary?.remainingPercent == 91)
    }

    @Test
    func loadSnapshotSupportsNativeRegistryUsageShapeWithoutRemainingPercent() throws {
        let fixture = try Fixture.make(includeUsage: false, registryData: Fixture.registryDataWithNativeStoredUsage)
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        let snapshot = try store.loadSnapshot()

        #expect(snapshot.activeAccount?.accountKey == "user-a::acct-a")
        #expect(snapshot.usage?.primary?.usedPercent == 12)
        #expect(snapshot.usage?.primary?.remainingPercent == 88)
        #expect(snapshot.usage?.secondary?.usedPercent == 14)
        #expect(snapshot.usage?.secondary?.remainingPercent == 86)
    }

    @Test
    func loadSnapshotPrefersTargetAccountHistoryAfterSwitchWithoutNewSession() throws {
        let fixture = try Fixture.make(registryData: Fixture.registryDataWithStoredUsage)
        let store = CodexDataStore(paths: fixture.paths, fileManager: .default)

        try store.switchAccount(accountKey: "user-b::acct-b")
        let snapshot = try store.loadSnapshot()

        #expect(snapshot.activeAccount?.accountKey == "user-b::acct-b")
        #expect(snapshot.usage?.primary?.remainingPercent == 77)
        #expect(snapshot.usage?.secondary?.remainingPercent == 95)
    }

    @Test
    func loadRegistryRetriesWhenFileIsTemporarilyMissing() throws {
        let fixture = try Fixture.make()
        let registryURL = fixture.paths.registryFile
        let registryData = try Data(contentsOf: registryURL)
        var readCount = 0
        var sleepCount = 0
        let store = CodexDataStore(
            paths: fixture.paths,
            fileManager: .default,
            readData: { url in
                readCount += 1
                if url == registryURL, readCount == 1 {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                return registryData
            },
            sleepAction: { _ in
                sleepCount += 1
            },
            registryReadRetryCount: 3,
            registryReadRetryDelay: 0
        )

        let registry = try store.loadRegistry()

        #expect(registry.activeAccountKey == "user-a::acct-a")
        #expect(readCount == 2)
        #expect(sleepCount == 1)
    }
}

private struct Fixture {
    let root: URL
    let paths: CodexPaths

    static func make(
        includeUsage: Bool = true,
        sessionData: String = sessionDataDirect,
        registryData: Data = registryDataDefault
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        let paths = CodexPaths(root: root)

        try FileManager.default.createDirectory(at: paths.accountsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.sessionsDirectory.appendingPathComponent("2026/03/25"), withIntermediateDirectories: true)

        try registryData.write(to: paths.registryFile)
        try Data("{\"tokens\":{\"account_id\":\"acct-a\"}}".utf8).write(to: paths.authFile)
        try Data("{\"tokens\":{\"account_id\":\"acct-a\"}}".utf8).write(to: paths.accountsDirectory.appendingPathComponent("dXNlci1hOjphY2N0LWE.auth.json"))
        try Data("{\"tokens\":{\"account_id\":\"acct-b\"}}".utf8).write(to: paths.accountsDirectory.appendingPathComponent("dXNlci1iOjphY2N0LWI.auth.json"))

        if includeUsage {
            let sessionURL = paths.sessionsDirectory
                .appendingPathComponent("2026/03/25/sample.jsonl")
            try Data(sessionData.utf8).write(to: sessionURL)
        }

        return Fixture(root: root, paths: paths)
    }

    private static let registryDataDefault = Data("""
    {
      "schema_version": 3,
      "active_account_key": "user-a::acct-a",
      "active_account_activated_at_ms": 1774417805900,
      "accounts": [
        {
          "account_key": "user-a::acct-a",
          "chatgpt_account_id": "acct-a",
          "chatgpt_user_id": "user-a",
          "email": "main@example.com",
          "alias": "",
          "plan": "plus",
          "auth_mode": "chatgpt",
          "created_at": 1774417805,
          "last_used_at": 1774417805
        },
        {
          "account_key": "user-b::acct-b",
          "chatgpt_account_id": "acct-b",
          "chatgpt_user_id": "user-b",
          "email": "alt@example.com",
          "alias": "Alt",
          "plan": "team",
          "auth_mode": "chatgpt",
          "created_at": 1774417805,
          "last_used_at": 1774417805
        }
      ]
    }
    """.utf8)

    static let registryDataWithStoredUsage = Data("""
    {
      "schema_version": 3,
      "active_account_key": "user-a::acct-a",
      "active_account_activated_at_ms": 1774417805900,
      "accounts": [
        {
          "account_key": "user-a::acct-a",
          "chatgpt_account_id": "acct-a",
          "chatgpt_user_id": "user-a",
          "email": "main@example.com",
          "alias": "",
          "plan": "plus",
          "auth_mode": "chatgpt",
          "created_at": 1774417805,
          "last_used_at": 1774417805,
          "last_usage_at": 1774418800,
          "last_local_rollout": "gpt-5",
          "last_usage": {
            "primary": {
              "used_percent": 42,
              "remaining_percent": 58,
              "reset_at": 1774435835
            },
            "secondary": {
              "used_percent": 9,
              "remaining_percent": 91,
              "reset_at": 1774937466
            }
          }
        },
        {
          "account_key": "user-b::acct-b",
          "chatgpt_account_id": "acct-b",
          "chatgpt_user_id": "user-b",
          "email": "alt@example.com",
          "alias": "Alt",
          "plan": "team",
          "auth_mode": "chatgpt",
          "created_at": 1774417805,
          "last_used_at": 1774417805,
          "last_usage_at": 1774419900,
          "last_local_rollout": "gpt-4.1",
          "last_usage": {
            "primary": {
              "used_percent": 23,
              "remaining_percent": 77,
              "reset_at": 1774436800
            },
            "secondary": {
              "used_percent": 5,
              "remaining_percent": 95,
              "reset_at": 1774938000
            }
          }
        }
      ]
    }
    """.utf8)

    static let registryDataWithNativeStoredUsage = Data("""
    {
      "schema_version": 3,
      "active_account_key": "user-a::acct-a",
      "active_account_activated_at_ms": 1774417805900,
      "auto_switch": {
        "enabled": false,
        "threshold_5h_percent": 10,
        "threshold_weekly_percent": 5
      },
      "api": {
        "usage": true
      },
      "accounts": [
        {
          "account_key": "user-a::acct-a",
          "chatgpt_account_id": "acct-a",
          "chatgpt_user_id": "user-a",
          "email": "main@example.com",
          "alias": "",
          "plan": "plus",
          "auth_mode": "chatgpt",
          "created_at": 1774417805,
          "last_used_at": 1774417805,
          "last_usage": {
            "primary": {
              "used_percent": 12,
              "window_minutes": null,
              "resets_at": null
            },
            "secondary": {
              "used_percent": 14,
              "window_minutes": null,
              "resets_at": null
            },
            "credits": null,
            "plan_type": null
          },
          "last_usage_at": 1774453021,
          "last_local_rollout": null
        }
      ]
    }
    """.utf8)

    private static let sessionDataDirect = """
    {"timestamp":"2026-03-25T06:32:54.896Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":27.0,"resets_at":1774435835},"secondary":{"used_percent":11.0,"resets_at":1774937466}}}}
    """

    static let nestedInfoSessionData = """
    {"timestamp":"2026-03-25T06:32:54.896Z","type":"event_msg","payload":{"type":"token_count","info":{"rate_limits":{"primary":{"used_percent":36.0,"resets_at":1774435835},"secondary":{"used_percent":7.0,"resets_at":1774937466}}}}}
    """
}
