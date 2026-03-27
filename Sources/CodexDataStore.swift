import Foundation

struct AppSnapshot {
    let accounts: [AccountSummary]
    let activeAccount: AccountSummary?
    let usage: UsageSnapshot?
    let activeAccessIssue: String?
}

struct AccountSummary: Identifiable, Equatable {
    let id: String
    let accountKey: String
    let email: String
    let alias: String
    let plan: String
    let isActive: Bool
    let usage: UsageSnapshot?
    let accessIssue: String?

    var displayName: String {
        if !alias.isEmpty {
            return alias
        }
        return email
    }

    var planLabel: String {
        plan.isEmpty ? "Unknown plan" : plan.uppercased()
    }

    var isAccessInvalid: Bool {
        accessIssue != nil
    }
}

struct UsageSnapshot: Codable, Equatable {
    let primary: UsageWindow?
    let secondary: UsageWindow?
}

struct UsageWindow: Codable, Equatable {
    let usedPercent: Int
    let remainingPercent: Int
    let resetAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case remainingPercent = "remaining_percent"
        case resetAt = "reset_at"
        case resetsAt = "resets_at"
    }

    init(usedPercent: Int, remainingPercent: Int, resetAt: Date?) {
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try Self.decodeInt(from: container, forKey: .usedPercent)
        if let remainingPercent = try container.decodeIfPresent(Int.self, forKey: .remainingPercent) {
            self.remainingPercent = remainingPercent
        } else {
            self.remainingPercent = max(0, 100 - usedPercent)
        }

        if let resetTimestamp = try container.decodeIfPresent(Int.self, forKey: .resetAt)
            ?? container.decodeIfPresent(Int.self, forKey: .resetsAt) {
            resetAt = Date(timeIntervalSince1970: TimeInterval(resetTimestamp))
        } else {
            resetAt = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(remainingPercent, forKey: .remainingPercent)
        try container.encodeIfPresent(resetAt.map { Int($0.timeIntervalSince1970) }, forKey: .resetAt)
        try container.encodeIfPresent(resetAt.map { Int($0.timeIntervalSince1970) }, forKey: .resetsAt)
    }

    var resetText: String {
        guard let resetAt else { return "Reset time unknown" }
        return "Resets \(Self.resetDateFormatter.string(from: resetAt))"
    }

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private static func decodeInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int {
        if let intValue = try container.decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let doubleValue = try container.decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleValue.rounded())
        }

        throw DecodingError.keyNotFound(
            key,
            .init(codingPath: container.codingPath, debugDescription: "Missing integer value for \(key.stringValue)")
        )
    }
}

struct CodexPaths {
    let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        self.root = root
    }

    var authFile: URL { root.appendingPathComponent("auth.json") }
    var accountsDirectory: URL { root.appendingPathComponent("accounts", isDirectory: true) }
    var registryFile: URL { accountsDirectory.appendingPathComponent("registry.json") }
    var sessionsDirectory: URL { root.appendingPathComponent("sessions", isDirectory: true) }

    func accountAuthFile(accountKey: String) -> URL {
        accountsDirectory.appendingPathComponent("\(encodeAccountKey(accountKey)).auth.json")
    }

    private func encodeAccountKey(_ accountKey: String) -> String {
        Data(accountKey.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum CodexStoreError: LocalizedError {
    case missingRegistry
    case missingAuthSnapshot(String)
    case invalidActiveAccount
    case invalidUsageData

    var errorDescription: String? {
        switch self {
        case .missingRegistry:
            return "Missing registry.json"
        case .missingAuthSnapshot(let key):
            return "Missing account snapshot: \(key)"
        case .invalidActiveAccount:
            return "Active account is invalid"
        case .invalidUsageData:
            return "Usage data is invalid"
        }
    }
}

final class CodexDataStore {
    typealias DataReader = (URL) throws -> Data
    typealias SleepAction = (TimeInterval) -> Void
    typealias UsageAPIClient = (ActiveUsageAuth) throws -> UsageAPIResult

    private let paths: CodexPaths
    private let fileManager: FileManager
    private let readData: DataReader
    private let sleepAction: SleepAction
    private let usageAPIClient: UsageAPIClient
    private let registryReadRetryCount: Int
    private let registryReadRetryDelay: TimeInterval
    private let decoder = JSONDecoder()
    private let sourceRootPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL.path
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(
        paths: CodexPaths = CodexPaths(),
        fileManager: FileManager = .default,
        readData: @escaping DataReader = { try Data(contentsOf: $0) },
        sleepAction: @escaping SleepAction = { Thread.sleep(forTimeInterval: $0) },
        usageAPIClient: @escaping UsageAPIClient = CodexDataStore.fetchUsageFromAPI,
        registryReadRetryCount: Int = 3,
        registryReadRetryDelay: TimeInterval = 0.05
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.readData = readData
        self.sleepAction = sleepAction
        self.usageAPIClient = usageAPIClient
        self.registryReadRetryCount = registryReadRetryCount
        self.registryReadRetryDelay = registryReadRetryDelay
    }

    func refreshAccountAccess(accountKey: String) throws {
        var registry = try loadRegistry()
        guard let index = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) else {
            throw CodexStoreError.invalidActiveAccount
        }

        let account = registry.accounts[index]
        let result = try fetchUsageForAccount(account)
        let nextIssue: String?
        if let accessIssue = result.accessIssue {
            nextIssue = accessIssue
        } else if result.snapshot != nil {
            nextIssue = nil
        } else {
            nextIssue = registry.accounts[index].lastAccessIssue
        }

        if registry.accounts[index].lastAccessIssue != nextIssue {
            registry.accounts[index].lastAccessIssue = nextIssue
            let registryData = try encoder.encode(registry)
            try writeAtomically(data: registryData, to: paths.registryFile)
        }
    }

    func loadSnapshot() throws -> AppSnapshot {
        var registry = try loadRegistry()
        let usageResolution = try resolveUsage(registry: &registry)
        let activeAccountKey = registry.activeAccountKey
        let accounts = registry.accounts.map { account in
            let accessIssue: String?
            if account.accountKey == activeAccountKey {
                accessIssue = usageResolution.accessIssue
            } else {
                accessIssue = account.lastAccessIssue
            }
            return AccountSummary(
                id: account.accountKey,
                accountKey: account.accountKey,
                email: account.email,
                alias: account.alias,
                plan: account.plan,
                isActive: account.accountKey == registry.activeAccountKey,
                usage: account.lastUsage,
                accessIssue: accessIssue
            )
        }
        let activeAccount = accounts.first(where: \.isActive)
        return AppSnapshot(
            accounts: accounts,
            activeAccount: activeAccount,
            usage: usageResolution.snapshot,
            activeAccessIssue: usageResolution.accessIssue
        )
    }

    func switchAccount(accountKey: String) throws {
        var registry = try loadRegistry()
        guard registry.accounts.contains(where: { $0.accountKey == accountKey }) else {
            throw CodexStoreError.invalidActiveAccount
        }

        let sourceAuthFile = paths.accountAuthFile(accountKey: accountKey)
        guard fileManager.fileExists(atPath: sourceAuthFile.path) else {
            throw CodexStoreError.missingAuthSnapshot(accountKey)
        }

        let authData = try Data(contentsOf: sourceAuthFile)
        try writeAtomically(data: authData, to: paths.authFile)

        registry.activeAccountKey = accountKey
        registry.activeAccountActivatedAtMS = Int(Date().timeIntervalSince1970 * 1000)
        if let index = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) {
            registry.accounts[index].lastUsedAt = Int(Date().timeIntervalSince1970)
        }

        let registryData = try encoder.encode(registry)
        try writeAtomically(data: registryData, to: paths.registryFile)
    }

    func removeAccount(accountKey: String) throws {
        var registry = try loadRegistry()
        guard let removedIndex = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) else {
            throw CodexStoreError.invalidActiveAccount
        }

        let removedAccount = registry.accounts[removedIndex]
        let remainingAccounts = registry.accounts.enumerated().compactMap { index, account in
            index == removedIndex ? nil : account
        }
        let removedSnapshotURL = paths.accountAuthFile(accountKey: removedAccount.accountKey)

        if removedAccount.accountKey == registry.activeAccountKey {
            if let nextAccount = remainingAccounts.first {
                let nextSnapshotURL = paths.accountAuthFile(accountKey: nextAccount.accountKey)
                guard fileManager.fileExists(atPath: nextSnapshotURL.path) else {
                    throw CodexStoreError.missingAuthSnapshot(nextAccount.accountKey)
                }

                let authData = try Data(contentsOf: nextSnapshotURL)
                try writeAtomically(data: authData, to: paths.authFile)
                registry.activeAccountKey = nextAccount.accountKey
                registry.activeAccountActivatedAtMS = Int(Date().timeIntervalSince1970 * 1000)
            } else {
                registry.activeAccountKey = ""
                registry.activeAccountActivatedAtMS = nil
                if fileManager.fileExists(atPath: paths.authFile.path) {
                    try fileManager.removeItem(at: paths.authFile)
                }
            }
        }

        registry.accounts = remainingAccounts
        let registryData = try encoder.encode(registry)
        try writeAtomically(data: registryData, to: paths.registryFile)

        if fileManager.fileExists(atPath: removedSnapshotURL.path) {
            try fileManager.removeItem(at: removedSnapshotURL)
        }
    }

    func validateAccountAccess(accountKey: String) throws {
        var registry = try loadRegistry()
        guard let accountIndex = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) else {
            throw CodexStoreError.invalidActiveAccount
        }

        let account = registry.accounts[accountIndex]
        guard let auth = try decodeUsageAuth(
            from: paths.accountAuthFile(accountKey: account.accountKey),
            fallbackAccountID: account.chatgptAccountID
        ) else {
            try cacheAccessIssueIfNeeded(
                "Account auth missing. Re-login required.",
                registry: &registry,
                activeIndex: accountIndex
            )
            return
        }

        let apiResult = try usageAPIClient(auth)
        if let snapshot = apiResult.snapshot {
            if account.lastUsage != snapshot {
                registry.accounts[accountIndex].lastUsage = snapshot
                registry.accounts[accountIndex].lastUsageAt = Int(Date().timeIntervalSince1970)
            }
            try cacheAccessIssueIfNeeded(nil, registry: &registry, activeIndex: accountIndex)
            return
        }

        if let accessIssue = apiResult.accessIssue {
            try cacheAccessIssueIfNeeded(accessIssue, registry: &registry, activeIndex: accountIndex)
        }
    }

    func loadRegistry() throws -> RegistryFile {
        let attempts = max(1, registryReadRetryCount)

        for attempt in 0..<attempts {
            do {
                let data = try readData(paths.registryFile)
                return try decoder.decode(RegistryFile.self, from: data)
            } catch {
                guard isMissingFileError(error) else {
                    throw error
                }

                if attempt == attempts - 1 {
                    throw CodexStoreError.missingRegistry
                }

                sleepAction(registryReadRetryDelay)
            }
        }

        throw CodexStoreError.missingRegistry
    }

    func loadLatestUsage() throws -> UsageSnapshot? {
        try loadLatestUsageRecord()?.snapshot
    }

    private func resolveUsage(registry: inout RegistryFile) throws -> UsageResolution {
        guard let activeIndex = registry.accounts.firstIndex(where: { $0.accountKey == registry.activeAccountKey }) else {
            return UsageResolution(snapshot: nil, accessIssue: nil)
        }

        let apiResult = try fetchActiveUsageFromAPI(registry: registry, activeIndex: activeIndex)
        if let apiUsage = apiResult.snapshot {
            try cacheUsageIfNeeded(apiUsage, registry: &registry, activeIndex: activeIndex)
            return UsageResolution(snapshot: apiUsage, accessIssue: nil)
        }

        if let accessIssue = apiResult.accessIssue {
            try cacheAccessIssueIfNeeded(accessIssue, registry: &registry, activeIndex: activeIndex)
            return UsageResolution(
                snapshot: registry.accounts[activeIndex].lastUsage,
                accessIssue: accessIssue
            )
        }

        if let latestUsage = try loadLatestUsageRecord(),
           shouldUseLatestUsage(latestUsage, for: registry) {
            try cacheUsageIfNeeded(
                latestUsage.snapshot,
                registry: &registry,
                activeIndex: activeIndex,
                timestamp: latestUsage.timestamp
            )
            try cacheAccessIssueIfNeeded(nil, registry: &registry, activeIndex: activeIndex)
            return UsageResolution(snapshot: latestUsage.snapshot, accessIssue: nil)
        }

        try cacheAccessIssueIfNeeded(nil, registry: &registry, activeIndex: activeIndex)
        return UsageResolution(
            snapshot: registry.accounts[activeIndex].lastUsage,
            accessIssue: registry.accounts[activeIndex].lastAccessIssue
        )
    }

    private func fetchActiveUsageFromAPI(registry: RegistryFile, activeIndex: Int) throws -> UsageAPIResult {
        let account = registry.accounts[activeIndex]
        guard let auth = try loadActiveUsageAuth(for: account) else {
            return UsageAPIResult(snapshot: nil, accessIssue: "Account auth missing. Re-login required.")
        }
        do {
            return try usageAPIClient(auth)
        } catch {
            return UsageAPIResult(snapshot: nil, accessIssue: nil)
        }
    }

    private func fetchUsageForAccount(_ account: RegistryAccount) throws -> UsageAPIResult {
        guard let auth = try loadActiveUsageAuth(for: account) else {
            return UsageAPIResult(snapshot: nil, accessIssue: "Account auth missing. Re-login required.")
        }

        do {
            return try usageAPIClient(auth)
        } catch {
            return UsageAPIResult(snapshot: nil, accessIssue: nil)
        }
    }

    private func loadActiveUsageAuth(for account: RegistryAccount) throws -> ActiveUsageAuth? {
        if let currentAuth = try decodeUsageAuth(from: paths.authFile),
           currentAuth.accountID == account.chatgptAccountID {
            return currentAuth
        }

        return try decodeUsageAuth(
            from: paths.accountAuthFile(accountKey: account.accountKey),
            fallbackAccountID: account.chatgptAccountID
        )
    }

    private func decodeUsageAuth(from url: URL, fallbackAccountID: String? = nil) throws -> ActiveUsageAuth? {
        let data = try readData(url)
        let auth = try decoder.decode(AuthFile.self, from: data)
        guard auth.authMode != "apikey" else {
            return nil
        }

        guard let accessToken = auth.tokens?.accessToken,
              let accountID = auth.tokens?.accountID ?? fallbackAccountID,
              !accessToken.isEmpty,
              !accountID.isEmpty else {
            return nil
        }

        return ActiveUsageAuth(accessToken: accessToken, accountID: accountID)
    }

    private func cacheUsageIfNeeded(
        _ usage: UsageSnapshot,
        registry: inout RegistryFile,
        activeIndex: Int,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        let account = registry.accounts[activeIndex]
        let rollout = account.lastLocalRollout
        if account.lastUsage != usage || account.lastUsageAt != timestamp {
            registry.accounts[activeIndex].lastUsage = usage
            registry.accounts[activeIndex].lastUsageAt = timestamp
            registry.accounts[activeIndex].lastLocalRollout = rollout
            let registryData = try encoder.encode(registry)
            try writeAtomically(data: registryData, to: paths.registryFile)
        }
    }

    private func cacheAccessIssueIfNeeded(
        _ accessIssue: String?,
        registry: inout RegistryFile,
        activeIndex: Int
    ) throws {
        if registry.accounts[activeIndex].lastAccessIssue != accessIssue {
            registry.accounts[activeIndex].lastAccessIssue = accessIssue
            let registryData = try encoder.encode(registry)
            try writeAtomically(data: registryData, to: paths.registryFile)
        }
    }

    private func shouldUseLatestUsage(_ usage: UsageRecord, for registry: RegistryFile) -> Bool {
        guard let activatedAtMS = registry.activeAccountActivatedAtMS else {
            return true
        }
        return usage.modifiedAt.timeIntervalSince1970 * 1000 >= TimeInterval(activatedAtMS)
    }

    private func loadLatestUsageRecord() throws -> UsageRecord? {
        guard fileManager.fileExists(atPath: paths.sessionsDirectory.path) else {
            return nil
        }

        let enumerator = fileManager.enumerator(
            at: paths.sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var files: [(url: URL, modifiedAt: Date)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            files.append((url, values.contentModificationDate ?? .distantPast))
        }

        for candidate in files.sorted(by: { $0.modifiedAt > $1.modifiedAt }) {
            let content = try String(contentsOf: candidate.url, encoding: .utf8)
            guard !shouldSkipSessionFile(content) else {
                continue
            }
            for line in content.split(separator: "\n").reversed() {
                guard let data = line.data(using: .utf8) else { continue }
                if let event = try? decoder.decode(SessionEvent.self, from: data),
                   event.type == "event_msg",
                   event.payload.type == "token_count" {
                    return UsageRecord(
                        snapshot: UsageSnapshot(
                            primary: UsageWindow(event.payload.rateLimits?.primary),
                            secondary: UsageWindow(event.payload.rateLimits?.secondary)
                        ),
                        modifiedAt: candidate.modifiedAt,
                        timestamp: Int(candidate.modifiedAt.timeIntervalSince1970)
                    )
                }
            }
        }

        return nil
    }

    private func shouldSkipSessionFile(_ content: String) -> Bool {
        guard let firstLine = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first,
              let data = firstLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else {
            return false
        }

        if payload["agent_role"] != nil {
            return true
        }

        if let source = payload["source"] as? [String: Any], source["subagent"] != nil {
            return true
        }

        if let cwd = payload["cwd"] as? String,
           URL(fileURLWithPath: cwd).standardizedFileURL.path.hasPrefix(sourceRootPath) {
            return true
        }

        return false
    }

    private func writeAtomically(data: Data, to destination: URL) throws {
        let tempURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp.\(UUID().uuidString)")
        try data.write(to: tempURL)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: destination)
        }
    }
}

private extension CodexDataStore {
    static func fetchUsageFromAPI(auth: ActiveUsageAuth) throws -> UsageAPIResult {
        let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(auth.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("CodexAuthMacOSBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let box = UsageHTTPResultBox()

        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.error = error
            box.statusCode = (response as? HTTPURLResponse)?.statusCode
            box.semaphore.signal()
        }.resume()

        box.semaphore.wait()

        if let responseError = box.error {
            throw responseError
        }

        guard let statusCode = box.statusCode else {
            return UsageAPIResult(snapshot: nil, accessIssue: nil)
        }

        if (400..<500).contains(statusCode), statusCode != 429 {
            return UsageAPIResult(snapshot: nil, accessIssue: "Account access invalid. Re-login required.")
        }

        guard (200..<300).contains(statusCode), let responseData = box.data else {
            return UsageAPIResult(snapshot: nil, accessIssue: nil)
        }

        if let responseText = String(data: responseData, encoding: .utf8)?
            .lowercased(),
           responseText.contains("not a member")
            || responseText.contains("workspace")
            || responseText.contains("forbidden")
            || responseText.contains("unauthorized")
            || responseText.contains("access denied") {
            return UsageAPIResult(snapshot: nil, accessIssue: "Account access invalid. Re-login required.")
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(UsageAPIResponse.self, from: responseData)
        let snapshot = UsageSnapshot(
            primary: UsageWindow(response.rateLimit?.primaryWindow),
            secondary: UsageWindow(response.rateLimit?.secondaryWindow)
        )

        if snapshot.primary == nil, snapshot.secondary == nil {
            return UsageAPIResult(snapshot: nil, accessIssue: nil)
        }

        return UsageAPIResult(snapshot: snapshot, accessIssue: nil)
    }
}

private final class UsageHTTPResultBox: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var data: Data?
    var error: Error?
    var statusCode: Int?
}

private func isMissingFileError(_ error: Error) -> Bool {
    guard let cocoaError = error as? CocoaError else {
        return false
    }
    return cocoaError.code == .fileReadNoSuchFile
}

private struct UsageRecord {
    let snapshot: UsageSnapshot
    let modifiedAt: Date
    let timestamp: Int
}

private struct UsageResolution {
    let snapshot: UsageSnapshot?
    let accessIssue: String?
}

private extension UsageWindow {
    init?(_ source: RateLimitWindow?) {
        guard let source else { return nil }
        let usedPercent = Int(source.usedPercent.rounded())
        self.usedPercent = usedPercent
        self.remainingPercent = max(0, 100 - usedPercent)
        self.resetAt = source.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

struct RegistryFile: Codable {
    let schemaVersion: Int
    var activeAccountKey: String
    var activeAccountActivatedAtMS: Int?
    var autoSwitch: RegistryAutoSwitch?
    var api: RegistryAPI?
    var accounts: [RegistryAccount]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case activeAccountKey = "active_account_key"
        case activeAccountActivatedAtMS = "active_account_activated_at_ms"
        case autoSwitch = "auto_switch"
        case api
        case accounts
    }
}

struct RegistryAutoSwitch: Codable {
    let enabled: Bool
}

struct RegistryAPI: Codable {
    let usage: Bool?
}

struct RegistryAccount: Codable {
    let accountKey: String
    let chatgptAccountID: String?
    let chatgptUserID: String?
    let email: String
    let alias: String
    let plan: String
    let authMode: String
    let createdAt: Int?
    var lastUsedAt: Int?
    var lastUsage: UsageSnapshot?
    var lastUsageAt: Int?
    var lastLocalRollout: String?
    var lastAccessIssue: String?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case chatgptAccountID = "chatgpt_account_id"
        case chatgptUserID = "chatgpt_user_id"
        case email
        case alias
        case plan
        case authMode = "auth_mode"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case lastLocalRollout = "last_local_rollout"
        case lastAccessIssue = "last_access_issue"
    }
}

struct SessionEvent: Decodable {
    let type: String
    let payload: SessionPayload
}

struct SessionPayload: Decodable {
    let type: String
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
        case info
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        if let directLimits = try container.decodeIfPresent(RateLimits.self, forKey: .rateLimits) {
            rateLimits = directLimits
            return
        }

        if let info = try container.decodeIfPresent(SessionInfo.self, forKey: .info) {
            rateLimits = info.rateLimits
            return
        }

        rateLimits = nil
    }
}

struct SessionInfo: Decodable {
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

struct RateLimits: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case resetAt = "reset_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        resetsAt = try container.decodeIfPresent(Int.self, forKey: .resetsAt)
            ?? container.decodeIfPresent(Int.self, forKey: .resetAt)
    }
}

struct ActiveUsageAuth {
    let accessToken: String
    let accountID: String
}

struct UsageAPIResult {
    let snapshot: UsageSnapshot?
    let accessIssue: String?
}

private struct AuthFile: Decodable {
    let authMode: String?
    let tokens: AuthTokens?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case tokens
    }
}

private struct AuthTokens: Decodable {
    let accessToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}

private struct UsageAPIResponse: Decodable {
    let rateLimit: UsageAPIRateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
}

private struct UsageAPIRateLimit: Decodable {
    let primaryWindow: RateLimitWindow?
    let secondaryWindow: RateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}
