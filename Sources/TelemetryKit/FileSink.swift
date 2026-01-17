import Foundation

public final class FileTelemetrySink: TelemetrySink {
    private let directoryURL: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    public init(
        directoryURL: URL = URL(fileURLWithPath: "TelemetryLogs", isDirectory: true),
        fileName: String = "events.jsonl",
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent(fileName)
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        ensureDirectory()
    }

    public func record(_ event: TelemetryEvent) {
        guard let data = try? encoder.encode(event) else { return }
        let lineData = data + Data("\n".utf8)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
        }
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}
