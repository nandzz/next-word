import Foundation

enum CodexCLILocator {
    static let shared = CLILocator(binary: "codex", usesLoginShellPath: true) { home in
        var paths = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.volta/bin/codex",
        ]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            paths += versions.sorted(by: >).map { "\(nvm)/\($0)/bin/codex" }
        }
        return paths
    }

    static var candidatePaths: [String] { shared.candidatePaths }

    static func locate(customPath: String?) -> URL? { shared.locate(customPath: customPath) }

    static func resolve(customPath: String?) -> URL? { shared.resolve(customPath: customPath) }

    static func version(at url: URL) async -> String? { await shared.version(at: url) }

    static func environment(for url: URL) -> [String: String] { shared.environment(for: url) }
}
