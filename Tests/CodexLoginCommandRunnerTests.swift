import Foundation
import Testing
@testable import CodexAuthMacOSBar

struct CodexLoginCommandRunnerTests {
    @Test
    func resolveCommandPrefersHomebrewCodex() {
        let runner = CodexLoginCommandRunner()
        let command = runner.resolveCommand(
            fileManager: ExecutableFileManager(),
            preferredPath: "/opt/homebrew/bin/codex"
        )

        #expect(command.executableURL.path == "/opt/homebrew/bin/codex")
        #expect(command.arguments == ["login"])
    }

    @Test
    func resolveCommandFallsBackToEnvWhenHomebrewCodexMissing() {
        let runner = CodexLoginCommandRunner()
        let command = runner.resolveCommand(fileManager: EmptyExecutableFileManager())

        #expect(command.executableURL.path == "/usr/bin/env")
        #expect(command.arguments == ["codex", "login"])
    }

    @Test
    func resultForTerminationTreatsSignalAsCancelled() {
        let result = CodexLoginCommandRunner.resultForTermination(
            status: 15,
            reason: .uncaughtSignal
        )

        switch result {
        case .failure(let error):
            #expect(error == .cancelled)
        case .success:
            Issue.record("expected cancelled result")
        }
    }

    @Test
    func forceKillIfNeededEscalatesToSigkillWhenProcessStillRunning() async {
        let process = HangingProcess(processIdentifier: 4242, isRunning: true)
        let recorder = SignalRecorder()

        await CodexLoginCommandRunner.forceKillIfNeeded(
            process: process,
            gracePeriodNanoseconds: 0,
            sleep: { _ in },
            signalSender: { pid, signal in
                recorder.record(pid: pid, signal: signal)
                return 0
            }
        )

        let sentSignals = recorder.values()
        #expect(sentSignals.count == 1)
        #expect(sentSignals.first?.0 == 4242)
        #expect(sentSignals.first?.1 == SIGKILL)
    }
}

private final class ExecutableFileManager: FileManager, @unchecked Sendable {
    override func isExecutableFile(atPath path: String) -> Bool {
        true
    }
}

private final class EmptyExecutableFileManager: FileManager, @unchecked Sendable {
    override func isExecutableFile(atPath path: String) -> Bool {
        false
    }
}

private final class HangingProcess: Process, @unchecked Sendable {
    private let mockedProcessIdentifier: pid_t
    private let mockedIsRunning: Bool

    init(processIdentifier: pid_t, isRunning: Bool) {
        self.mockedProcessIdentifier = processIdentifier
        self.mockedIsRunning = isRunning
        super.init()
    }

    override var processIdentifier: Int32 {
        mockedProcessIdentifier
    }

    override var isRunning: Bool {
        mockedIsRunning
    }
}

private final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sentSignals: [(pid_t, Int32)] = []

    func record(pid: pid_t, signal: Int32) {
        lock.lock()
        defer { lock.unlock() }
        sentSignals.append((pid, signal))
    }

    func values() -> [(pid_t, Int32)] {
        lock.lock()
        defer { lock.unlock() }
        return sentSignals
    }
}
