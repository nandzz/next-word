import Foundation
import os
import Testing
@testable import NextWord

struct ClaudeCLILocatorEnvironmentTests {
    private let binary = URL(fileURLWithPath: "/tmp/nextword-tests/custom-bin/claude")

    private func pathComponents() -> [String] {
        (ClaudeCLILocator.environment(for: binary)["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    @Test func pathStartsWithBinaryDirectory() {
        #expect(pathComponents().first == "/tmp/nextword-tests/custom-bin")
    }

    @Test(arguments: ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
    func pathContainsStandardDirectory(directory: String) {
        #expect(pathComponents().contains(directory))
    }

    @Test func pathContainsUserLocalBin() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(pathComponents().contains("\(home)/.local/bin"))
    }

    @Test func pathHasNoDuplicatesOrEmptyEntries() {
        let components = pathComponents()
        #expect(Set(components).count == components.count)
        #expect(!components.contains(""))
    }

    @Test func pathKeepsExistingProcessPath() {
        let existing = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let components = pathComponents()
        for entry in existing where !entry.isEmpty {
            #expect(components.contains(entry))
        }
    }

    @Test func removesClaudeCodeVariables() {
        setenv("CLAUDECODE", "1", 1)
        setenv("CLAUDE_CODE_ENTRYPOINT", "cli", 1)
        let env = ClaudeCLILocator.environment(for: binary)
        #expect(env["CLAUDECODE"] == nil)
        #expect(env["CLAUDE_CODE_ENTRYPOINT"] == nil)
    }

    @Test func setsHome() {
        #expect(ClaudeCLILocator.environment(for: binary)["HOME"]?.isEmpty == false)
    }
}

struct CLILocatorCacheTests {
    @Test func failedLookupIsNotRetriedWithinInterval() {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let locator = CLILocator(binary: "nextword-missing-binary-\(UUID().uuidString.prefix(8))") { _ in
            calls.withLock { $0 += 1 }
            return []
        }
        #expect(locator.resolve(customPath: nil) == nil)
        #expect(locator.resolve(customPath: nil) == nil)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func resolvedCustomPathIsCached() {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let locator = CLILocator(binary: "sh") { _ in
            calls.withLock { $0 += 1 }
            return []
        }
        #expect(locator.resolve(customPath: "/bin/sh")?.path == "/bin/sh")
        #expect(locator.resolve(customPath: " /bin/sh ")?.path == "/bin/sh")
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func cacheIsKeptPerCustomPath() {
        let locator = CLILocator(binary: "nextword-missing-binary") { _ in ["/bin/ls"] }
        #expect(locator.resolve(customPath: "/bin/sh")?.path == "/bin/sh")
        #expect(locator.resolve(customPath: nil)?.path == "/bin/ls")
        #expect(locator.resolve(customPath: "/bin/sh")?.path == "/bin/sh")
    }

    @Test func locateRefreshesCache() {
        let paths = OSAllocatedUnfairLock(initialState: ["/bin/ls"])
        let locator = CLILocator(binary: "nextword-missing-binary") { _ in paths.withLock { $0 } }
        #expect(locator.resolve(customPath: nil)?.path == "/bin/ls")
        paths.withLock { $0 = ["/bin/cat"] }
        #expect(locator.resolve(customPath: nil)?.path == "/bin/ls")
        #expect(locator.locate(customPath: nil)?.path == "/bin/cat")
        #expect(locator.resolve(customPath: nil)?.path == "/bin/cat")
    }

    @Test func codexAndClaudeShareStandardPath() {
        let binary = URL(fileURLWithPath: "/tmp/nextword-tests/custom-bin/codex")
        let components = (CodexCLILocator.environment(for: binary)["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(components.first == "/tmp/nextword-tests/custom-bin")
        #expect(Set(components).count == components.count)
        #expect(components.contains("/usr/bin"))
    }
}
