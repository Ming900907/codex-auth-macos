import Foundation

struct AppSnapshot {
    let accounts: [AccountSummary]
    let activeAccount: AccountSummary?
    let usage: UsageSnapshot?
}

struct AccountSummary: Identifiable, Equatable {
    let id: String
    let accountKey: String
    let email: String
    let alias: String
    let plan: String
    let isActive: Bool

    var displayName: String {
        if !alias.isEmpty {
            return alias
        }
        return email
    }

    var planLabel: String {
        plan.isEmpty ? "未知套餐" : plan.uppercased()
    }
}

struct UsageSnapshot: Equatable {
    let primary: UsageWindow?
    let secondary: UsageWindow?
}

struct UsageWindow: Equatable {
    let usedPercent: Int
    let remainingPercent: Int
    let resetAt: Date?

    var resetText: String {
        guard let resetAt else { return "重置时间未知" }
        return "重置 \(Self.resetDateFormatter.string(from: resetAt))"
    }

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
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
            return "缺少 registry.json"
        case .missingAuthSnapshot(let key):
            return "缺少账号快照：\(key)"
        case .invalidActiveAccount:
            return "当前账号信息无效"
        case .invalidUsageData:
            return "额度数据格式无效"
        }
    }
}

final class CodexDataStore {
    private let paths: CodexPaths
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(paths: CodexPaths = CodexPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func loadSnapshot() throws -> AppSnapshot {
        let registry = try loadRegistry()
        let accounts = registry.accounts.map { account in
            AccountSummary(
                id: account.accountKey,
                accountKey: account.accountKey,
                email: account.email,
                alias: account.alias,
                plan: account.plan,
                isActive: account.accountKey == registry.activeAccountKey
            )
        }
        let activeAccount = accounts.first(where: \.isActive)
        let usage = try loadLatestUsage()
        return AppSnapshot(accounts: accounts, activeAccount: activeAccount, usage: usage)
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

    func loadRegistry() throws -> RegistryFile {
        guard fileManager.fileExists(atPath: paths.registryFile.path) else {
            throw CodexStoreError.missingRegistry
        }
        let data = try Data(contentsOf: paths.registryFile)
        return try decoder.decode(RegistryFile.self, from: data)
    }

    func loadLatestUsage() throws -> UsageSnapshot? {
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

        for candidate in files.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(20) {
            let content = try String(contentsOf: candidate.url, encoding: .utf8)
            for line in content.split(separator: "\n").reversed() {
                guard let data = line.data(using: .utf8) else { continue }
                if let event = try? decoder.decode(SessionEvent.self, from: data),
                   event.type == "event_msg",
                   event.payload.type == "token_count" {
                    return UsageSnapshot(
                        primary: UsageWindow(event.payload.rateLimits?.primary),
                        secondary: UsageWindow(event.payload.rateLimits?.secondary)
                    )
                }
            }
        }

        return nil
    }

    private func writeAtomically(data: Data, to destination: URL) throws {
        let tempURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp.\(UUID().uuidString)")
        try data.write(to: tempURL, options: .completeFileProtectionUnlessOpen)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: destination)
        }
    }
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
    }
}
