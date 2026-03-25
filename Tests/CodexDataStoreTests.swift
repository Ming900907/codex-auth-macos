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

        #expect(usage.resetText.contains("2026-03-25"))
        #expect(usage.resetText.contains(":"))
    }
}

private struct Fixture {
    let root: URL
    let paths: CodexPaths

    static func make(includeUsage: Bool = true, sessionData: String = sessionDataDirect) throws -> Fixture {
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

    private static let registryData = Data("""
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

    private static let sessionDataDirect = """
    {"timestamp":"2026-03-25T06:32:54.896Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":27.0,"resets_at":1774435835},"secondary":{"used_percent":11.0,"resets_at":1774937466}}}}
    """

    static let nestedInfoSessionData = """
    {"timestamp":"2026-03-25T06:32:54.896Z","type":"event_msg","payload":{"type":"token_count","info":{"rate_limits":{"primary":{"used_percent":36.0,"resets_at":1774435835},"secondary":{"used_percent":7.0,"resets_at":1774937466}}}}}
    """
}
