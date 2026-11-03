import Foundation
import OSLog

enum DebugLog {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NextWord/NextWord.log")

    private static let logger = Logger(subsystem: AppInfo.bundleID, category: "app")
    private static let queue = DispatchQueue(label: "\(AppInfo.bundleID).debuglog")
    private static let maxFileSize: UInt64 = 1_000_000

    static func write(_ message: String) {
        logger.debug("\(message, privacy: .private)")
        #if DEBUG
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        queue.async { append(line) }
        #endif
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64, size > maxFileSize {
            try? manager.removeItem(at: fileURL)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            try? Data(line.utf8).write(to: fileURL)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

enum AppInfo {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.nandzz.nextword"
}
