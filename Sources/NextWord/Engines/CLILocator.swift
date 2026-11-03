import Foundation
import os

final class CLILocator: Sendable {
    static let retryInterval: TimeInterval = 60
    static let systemPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    private struct Lookup {
        var customPath: String?
        var url: URL?
        var date: Date
    }

    private struct ShellPath {
        var value: String?
        var date: Date
    }

    let binary: String
    let usesLoginShellPath: Bool
    private let candidates: @Sendable (String) -> [String]
    private let lookups = OSAllocatedUnfairLock<[Lookup]>(initialState: [])
    private let shellPath = OSAllocatedUnfairLock<ShellPath?>(initialState: nil)

    init(binary: String, usesLoginShellPath: Bool = false, candidates: @escaping @Sendable (String) -> [String]) {
        self.binary = binary
        self.usesLoginShellPath = usesLoginShellPath
        self.candidates = candidates
    }

    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    var candidatePaths: [String] { candidates(Self.home) }

    func locate(customPath: String?) -> URL? {
        let key = Self.normalized(customPath)
        let url = lookUp(customPath: key)
        lookups.withLock { entries in
            entries.removeAll { $0.customPath == key }
            entries.append(Lookup(customPath: key, url: url, date: Date()))
        }
        return url
    }

    func resolve(customPath: String?) -> URL? {
        let key = Self.normalized(customPath)
        if let cached = lookups.withLock({ $0.first { $0.customPath == key } }) {
            if let url = cached.url, Self.isExecutable(url.path) { return url }
            if cached.url == nil, Date().timeIntervalSince(cached.date) < Self.retryInterval { return nil }
        }
        return locate(customPath: key)
    }

    func version(at url: URL) async -> String? {
        guard let result = try? await ProcessRunner.run(
            executable: url,
            arguments: ["--version"],
            environment: environment(for: url),
            currentDirectory: FileManager.default.temporaryDirectory,
            timeout: 10
        ), result.status == 0, !result.timedOut else { return nil }
        let line = result.stdoutString
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return line?.isEmpty == false ? line : nil
    }

    func environment(for url: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        let home = Self.home
        if env["HOME"] == nil { env["HOME"] = home }

        let binaryDirectories = [
            url.deletingLastPathComponent().path,
            url.resolvingSymlinksInPath().deletingLastPathComponent().path,
        ]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        let shell = usesLoginShellPath ? (loginShellPath() ?? "").split(separator: ":").map(String.init) : []
        var seen = Set<String>()
        env["PATH"] = (binaryDirectories + ["\(home)/.local/bin"] + Self.systemPaths + existing + shell)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        return env
    }

    private func lookUp(customPath: String?) -> URL? {
        if let customPath, Self.isExecutable(customPath) {
            return URL(fileURLWithPath: customPath)
        }
        if let path = candidatePaths.first(where: Self.isExecutable) {
            return URL(fileURLWithPath: path)
        }
        let path = Self.runInLoginShell("command -v \(binary)")?
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") && Self.isExecutable($0) }
        return path.map { URL(fileURLWithPath: $0) }
    }

    private func loginShellPath() -> String? {
        if let cached = shellPath.withLock({ $0 }),
           cached.value != nil || Date().timeIntervalSince(cached.date) < Self.retryInterval {
            return cached.value
        }
        let value = Self.runInLoginShell(#"printf %s "$PATH""#)?
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 }
        shellPath.withLock { $0 = ShellPath(value: value, date: Date()) }
        return value
    }

    private static func normalized(_ customPath: String?) -> String? {
        guard let customPath else { return nil }
        let expanded = (customPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        return expanded.isEmpty ? nil : expanded
    }

    static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private static func runInLoginShell(_ command: String) -> String? {
        let result = ProcessRunner.runSync(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lic", command],
            currentDirectory: FileManager.default.temporaryDirectory,
            timeout: 5
        )
        guard !result.timedOut else { return nil }
        let output = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}
