import Darwin
import Foundation

enum CodexLoginError: LocalizedError, Equatable {
    case launchFailed(String)
    case failed(Int32)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Unable to launch codex login: \(message)"
        case .failed(let status):
            return "codex login failed with exit code \(status)"
        case .cancelled:
            return "Login cancelled"
        }
    }
}

struct CodexLoginCommand {
    let executableURL: URL
    let arguments: [String]
}

final class CodexLoginCommandRunner: @unchecked Sendable {
    typealias Sleep = @Sendable (UInt64) async -> Void
    typealias SignalSender = @Sendable (pid_t, Int32) -> Int32

    private let state = State()
    private let cancelGracePeriodNanoseconds: UInt64
    private let sleep: Sleep
    private let signalSender: SignalSender

    init(
        cancelGracePeriodNanoseconds: UInt64 = 750_000_000,
        sleep: @escaping Sleep = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        signalSender: @escaping SignalSender = { pid, signal in
            kill(pid, signal)
        }
    ) {
        self.cancelGracePeriodNanoseconds = cancelGracePeriodNanoseconds
        self.sleep = sleep
        self.signalSender = signalSender
    }

    func runLogin() async throws {
        let command = resolveCommand(fileManager: .default)
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        try await withCheckedThrowingContinuation { continuation in
            state.store(process: process, continuation: continuation)

            process.terminationHandler = { process in
                let result = Self.resultForTermination(
                    status: process.terminationStatus,
                    reason: process.terminationReason
                )
                self.state.finish(with: result.mapError { $0 as Error })
            }

            do {
                try process.run()
            } catch {
                state.finish(with: .failure(CodexLoginError.launchFailed(error.localizedDescription)))
            }
        }
    }

    func cancelLogin() {
        state.cancelProcess(
            gracePeriodNanoseconds: cancelGracePeriodNanoseconds,
            sleep: sleep,
            signalSender: signalSender
        )
    }

    func resolveCommand(
        fileManager: FileManager,
        preferredPath: String = "/opt/homebrew/bin/codex"
    ) -> CodexLoginCommand {
        if fileManager.isExecutableFile(atPath: preferredPath) {
            return CodexLoginCommand(
                executableURL: URL(fileURLWithPath: preferredPath),
                arguments: ["login"]
            )
        }

        return CodexLoginCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "login"]
        )
    }

    static func resultForTermination(
        status: Int32,
        reason: Process.TerminationReason
    ) -> Result<Void, CodexLoginError> {
        if reason == .uncaughtSignal {
            return .failure(.cancelled)
        }

        if status == 0 {
            return .success(())
        }

        return .failure(.failed(status))
    }

    static func forceKillIfNeeded(
        process: Process,
        gracePeriodNanoseconds: UInt64,
        sleep: @escaping Sleep,
        signalSender: @escaping SignalSender
    ) async {
        guard process.isRunning else { return }

        let pid = process.processIdentifier
        guard pid > 0 else { return }

        await sleep(gracePeriodNanoseconds)

        guard process.isRunning else { return }
        _ = signalSender(pid, SIGKILL)
    }
}

private final class State {
    private let lock = NSLock()
    private var process: Process?
    private var continuation: CheckedContinuation<Void, Error>?
    private var didFinish = false

    func store(process: Process, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        self.continuation = continuation
        didFinish = false
    }

    func finish(with result: Result<Void, Error>) {
        lock.lock()
        guard !didFinish, let continuation else {
            lock.unlock()
            return
        }

        didFinish = true
        process = nil
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func cancelProcess(
        gracePeriodNanoseconds: UInt64,
        sleep: @escaping CodexLoginCommandRunner.Sleep,
        signalSender: @escaping CodexLoginCommandRunner.SignalSender
    ) {
        lock.lock()
        let process = self.process
        lock.unlock()

        guard let process, process.isRunning else { return }
        process.terminate()

        Task {
            await CodexLoginCommandRunner.forceKillIfNeeded(
                process: process,
                gracePeriodNanoseconds: gracePeriodNanoseconds,
                sleep: sleep,
                signalSender: signalSender
            )
        }
    }
}
