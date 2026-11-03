import Foundation
import Testing
@testable import NextWord

struct ProcessRunnerTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test func returnsWhenBackgroundChildKeepsStdoutOpen() async throws {
        let start = Date()
        let result = try await ProcessRunner.run(executable: shell, arguments: ["-c", "sleep 30 & echo hi"], timeout: 2)
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == "hi")
    }

    @Test func runSyncReturnsWhenBackgroundChildKeepsStdoutOpen() {
        let start = Date()
        let result = ProcessRunner.runSync(executable: shell, arguments: ["-c", "sleep 30 & echo hi"], timeout: 2)
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(result.stdoutString.contains("hi"))
    }

    @Test func timesOutLongRunningProcess() async throws {
        let start = Date()
        let result = try await ProcessRunner.run(executable: shell, arguments: ["-c", "echo early; sleep 30"], timeout: 1)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(result.timedOut)
        #expect(result.stdoutString.contains("early"))
    }

    @Test func passesInputOnStdin() async throws {
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data("hello stdin".utf8), timeout: 5)
        #expect(result.status == 0)
        #expect(result.stdoutString == "hello stdin")
    }

    @Test func stdinIsEmptyWithoutInput() async throws {
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], timeout: 5)
        #expect(result.status == 0)
        #expect(result.stdout.isEmpty)
    }

    @Test func reportsExitStatusAndStderr() async throws {
        let result = try await ProcessRunner.run(executable: shell, arguments: ["-c", "echo oops >&2; exit 7"], timeout: 5)
        #expect(result.status == 7)
        #expect(result.stderrString == "oops\n")
        #expect(!result.timedOut)
    }

    @Test func passesEnvironmentAndDirectory() async throws {
        let result = try await ProcessRunner.run(
            executable: shell,
            arguments: ["-c", "printf '%s %s' \"$NEXTWORD_TEST\" \"$(pwd -P)\""],
            environment: ["NEXTWORD_TEST": "value"],
            currentDirectory: URL(fileURLWithPath: "/private/tmp"),
            timeout: 5
        )
        #expect(result.stdoutString == "value /private/tmp")
    }

    @Test func missingExecutableFailsQuickly() async throws {
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/nonexistent/nextword-binary"), arguments: [], timeout: 5)
        #expect(result.status == -1)
        #expect(!result.stderrString.isEmpty)
    }

    @Test func cancellationStopsProcess() async {
        let start = Date()
        let task = Task {
            try await ProcessRunner.run(executable: shell, arguments: ["-c", "sleep 30"], timeout: 60)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}
