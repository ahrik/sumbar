import Foundation

enum TestPaths {
    static func directory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temp/tests/" + UUID().uuidString)
    }
}
