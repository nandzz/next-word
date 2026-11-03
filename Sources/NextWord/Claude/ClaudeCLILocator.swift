import Foundation

enum ClaudeCLILocator {
    static let shared = CLILocator(binary: "claude") { home in
        [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
    }

    static var candidatePaths: [String] { shared.candidatePaths }

    static func locate(customPath: String?) -> URL? { shared.locate(customPath: customPath) }

    static func resolve(customPath: String?) -> URL? { shared.resolve(customPath: customPath) }

    static func version(at url: URL) async -> String? { await shared.version(at: url) }

    static func environment(for url: URL) -> [String: String] { shared.environment(for: url) }
}
