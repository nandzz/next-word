import Darwin
import Foundation
import os

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
    let timedOut: Bool
    let cancelled: Bool

    var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

final class ProcessHandle: @unchecked Sendable {
    static let exitGracePeriod: TimeInterval = 1
    static let killGracePeriod: TimeInterval = 1.5

    private let queue = DispatchQueue(label: "NextWord.ProcessHandle")
    private var pid: pid_t = 0
    private var exitStatus: Int32?
    private var stdout = Data()
    private var stderr = Data()
    private var openStreams = 0
    private var readSources: [DispatchSourceRead] = []
    private var exitSource: DispatchSourceProcess?
    private var timedOut = false
    private var cancelled = false
    private var finished = false
    private var completion: (@Sendable (ProcessResult) -> Void)?

    init() {}

    func cancel() {
        queue.async {
            guard !self.finished else { return }
            self.cancelled = true
            if self.completion != nil { self.stop() }
        }
    }

    fileprivate func launch(_ spec: ProcessRunner.Spec, completion: @escaping @Sendable (ProcessResult) -> Void) {
        queue.async {
            self.completion = completion
            guard !self.cancelled else {
                self.finish()
                return
            }
            let spawned: ProcessRunner.Spawned
            do {
                spawned = try ProcessRunner.spawn(spec)
            } catch {
                self.stderr.append(Data(error.localizedDescription.utf8))
                self.finish()
                return
            }
            self.pid = spawned.pid
            self.watchExit()
            self.read(spawned.stdout, toStdout: true)
            self.read(spawned.stderr, toStdout: false)
            if let stdin = spawned.stdin {
                ProcessRunner.write(spec.input ?? Data(), to: stdin)
            }
            if spec.timeout > 0 {
                self.queue.asyncAfter(deadline: .now() + spec.timeout) {
                    guard !self.finished else { return }
                    self.timedOut = true
                    self.stop()
                }
            }
        }
    }

    private func read(_ fd: Int32, toStdout: Bool) {
        openStreams += 1
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [unowned source] in
            var buffer = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                let data = Data(buffer[0..<count])
                if toStdout { self.stdout.append(data) } else { self.stderr.append(data) }
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                source.cancel()
                self.streamClosed()
            }
        }
        source.setCancelHandler { close(fd) }
        readSources.append(source)
        source.resume()
    }

    private func watchExit() {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { self.reap() }
        exitSource = source
        source.resume()
        reap()
    }

    private func reap() {
        guard exitStatus == nil, pid > 0 else { return }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        guard result == pid || (result == -1 && errno == ECHILD) else { return }
        exitStatus = result == pid ? Self.decode(status) : -1
        exitSource?.cancel()
        exitSource = nil
        if openStreams == 0 {
            finish()
            return
        }
        queue.asyncAfter(deadline: .now() + Self.exitGracePeriod) {
            guard !self.finished else { return }
            self.signalGroup(SIGTERM)
            self.finish()
        }
    }

    private func streamClosed() {
        openStreams -= 1
        if openStreams == 0, exitStatus != nil { finish() }
    }

    private func stop() {
        guard !finished else { return }
        if pid > 0 {
            signalGroup(SIGTERM)
            queue.asyncAfter(deadline: .now() + Self.killGracePeriod) { self.signalGroup(SIGKILL) }
        }
        finish()
    }

    private func signalGroup(_ signal: Int32) {
        guard pid > 0 else { return }
        if kill(-pid, signal) != 0, exitStatus == nil {
            kill(pid, signal)
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        for source in readSources { source.cancel() }
        readSources.removeAll()
        openStreams = 0
        let result = ProcessResult(
            status: exitStatus ?? -1,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut,
            cancelled: cancelled
        )
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private static func decode(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : signal
    }
}

enum ProcessRunner {
    fileprivate struct Spec {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]?
        let currentDirectory: URL?
        let input: Data?
        let timeout: TimeInterval
    }

    fileprivate struct Spawned {
        let pid: pid_t
        let stdin: Int32?
        let stdout: Int32
        let stderr: Int32
    }

    @discardableResult
    static func start(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval,
        handle: ProcessHandle = ProcessHandle(),
        completion: @escaping @Sendable (ProcessResult) -> Void
    ) -> ProcessHandle {
        let spec = Spec(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            input: input,
            timeout: timeout
        )
        handle.launch(spec, completion: completion)
        return handle
    }

    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let handle = ProcessHandle()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult, Never>) in
                start(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    currentDirectory: currentDirectory,
                    input: input,
                    timeout: timeout,
                    handle: handle
                ) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            handle.cancel()
        }
        if result.cancelled || Task.isCancelled { throw CancellationError() }
        return result
    }

    static func runSync(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval
    ) -> ProcessResult {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock<ProcessResult?>(initialState: nil)
        start(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            input: input,
            timeout: timeout
        ) { result in
            box.withLock { $0 = result }
            semaphore.signal()
        }
        semaphore.wait()
        return box.withLock { $0 } ?? ProcessResult(status: -1, stdout: Data(), stderr: Data(), timedOut: false, cancelled: false)
    }

    fileprivate static func spawn(_ spec: Spec) throws -> Spawned {
        var opened: [Int32] = []
        func makePipe() throws -> (read: Int32, write: Int32) {
            var fds: [Int32] = [0, 0]
            guard pipe(&fds) == 0 else { throw posixError() }
            opened += fds
            for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
            return (fds[0], fds[1])
        }

        let stdinPipe: (read: Int32, write: Int32)?
        let stdoutPipe: (read: Int32, write: Int32)
        let stderrPipe: (read: Int32, write: Int32)
        do {
            stdinPipe = spec.input == nil ? nil : try makePipe()
            stdoutPipe = try makePipe()
            stderrPipe = try makePipe()
        } catch {
            opened.forEach { close($0) }
            throw error
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let stdinPipe {
            posix_spawn_file_actions_adddup2(&actions, stdinPipe.read, STDIN_FILENO)
        } else {
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe.write, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe.write, STDERR_FILENO)
        if let directory = spec.currentDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for signal in [SIGPIPE, SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGCHLD] { sigaddset(&defaultSignals, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

        let path = spec.executable.path
        let argv = ([path] + spec.arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let environment = spec.environment ?? ProcessInfo.processInfo.environment
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        if let stdinPipe { close(stdinPipe.read) }
        close(stdoutPipe.write)
        close(stderrPipe.write)
        guard status == 0 else {
            if let stdinPipe { close(stdinPipe.write) }
            close(stdoutPipe.read)
            close(stderrPipe.read)
            throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO)
        }
        return Spawned(pid: pid, stdin: stdinPipe?.write, stdout: stdoutPipe.read, stderr: stderrPipe.read)
    }

    fileprivate static func write(_ data: Data, to fd: Int32) {
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            data.withUnsafeBytes { buffer in
                guard var pointer = buffer.baseAddress else { return }
                var remaining = buffer.count
                while remaining > 0 {
                    let written = Darwin.write(fd, pointer, remaining)
                    if written < 0 {
                        if errno == EINTR { continue }
                        break
                    }
                    remaining -= written
                    pointer += written
                }
            }
            close(fd)
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
