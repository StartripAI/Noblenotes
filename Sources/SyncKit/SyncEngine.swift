import Foundation
import CoreKit
import TelemetryKit

public struct Revision: Codable, Equatable {
    public let version: Int
    public let author: String
    public let timestamp: ISO8601Timestamp

    public init(version: Int, author: String, timestamp: ISO8601Timestamp = ISO8601Timestamp()) {
        self.version = version
        self.author = author
        self.timestamp = timestamp
    }
}

public struct SyncRecord: Codable, Equatable {
    public let id: String
    public let revision: Revision
    public let payload: String

    public init(id: String, revision: Revision, payload: String) {
        self.id = id
        self.revision = revision
        self.payload = payload
    }
}

public struct HistoryEntry: Codable, Equatable {
    public let recordId: String
    public let previousPayload: String
    public let revision: Revision

    public init(recordId: String, previousPayload: String, revision: Revision) {
        self.recordId = recordId
        self.previousPayload = previousPayload
        self.revision = revision
    }
}

public enum SyncError: Error, Equatable {
    case occConflict
}

public enum TextDiffKind: String, Codable {
    case insert
    case delete
    case replace
    case equal
}

public struct TextDiffOperation: Codable, Equatable {
    public let kind: TextDiffKind
    public let start: Int
    public let end: Int
    public let replacement: [String]

    public init(kind: TextDiffKind, start: Int, end: Int, replacement: [String]) {
        self.kind = kind
        self.start = start
        self.end = end
        self.replacement = replacement
    }
}

public struct TextDiff: Codable, Equatable {
    public let operations: [TextDiffOperation]

    public init(operations: [TextDiffOperation]) {
        self.operations = operations
    }
}

public protocol DiffEngine {
    func diff(base: String, updated: String) -> TextDiff
}

public struct LineDiffEngine: DiffEngine {
    public init() {}

    public func diff(base: String, updated: String) -> TextDiff {
        let baseLines = base.components(separatedBy: "\n")
        let updatedLines = updated.components(separatedBy: "\n")

        var prefix = 0
        while prefix < baseLines.count && prefix < updatedLines.count && baseLines[prefix] == updatedLines[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix + prefix < baseLines.count && suffix + prefix < updatedLines.count {
            if baseLines[baseLines.count - 1 - suffix] == updatedLines[updatedLines.count - 1 - suffix] {
                suffix += 1
            } else {
                break
            }
        }

        let baseMiddle = Array(baseLines[prefix..<(baseLines.count - suffix)])
        let updatedMiddle = Array(updatedLines[prefix..<(updatedLines.count - suffix)])

        var operations: [TextDiffOperation] = []
        if !baseMiddle.isEmpty || !updatedMiddle.isEmpty {
            let kind: TextDiffKind
            if baseMiddle.isEmpty {
                kind = .insert
            } else if updatedMiddle.isEmpty {
                kind = .delete
            } else {
                kind = .replace
            }
            let op = TextDiffOperation(kind: kind, start: prefix, end: prefix + baseMiddle.count, replacement: updatedMiddle)
            operations.append(op)
        }

        if operations.isEmpty {
            operations.append(TextDiffOperation(kind: .equal, start: 0, end: baseLines.count, replacement: baseLines))
        }

        return TextDiff(operations: operations)
    }
}

public struct MergeSuggestion: Codable, Equatable {
    public enum Strategy: String, Codable {
        case keepLocal
        case keepServer
        case autoMerge
    }

    public let strategy: Strategy
    public let preview: String
    public let mergedPayload: String?

    public init(strategy: Strategy, preview: String, mergedPayload: String?) {
        self.strategy = strategy
        self.preview = preview
        self.mergedPayload = mergedPayload
    }
}

public protocol ConflictResolver {
    func suggest(local: String, server: String, base: String?) -> [MergeSuggestion]
}

public struct RuleBasedConflictResolver: ConflictResolver {
    public init() {}

    public func suggest(local: String, server: String, base: String?) -> [MergeSuggestion] {
        if local == server {
            return [MergeSuggestion(strategy: .autoMerge, preview: "No changes detected.", mergedPayload: local)]
        }

        if let base {
            if local == base {
                return [MergeSuggestion(strategy: .keepServer, preview: "Local unchanged; prefer server.", mergedPayload: server)]
            }
            if server == base {
                return [MergeSuggestion(strategy: .keepLocal, preview: "Server unchanged; prefer local.", mergedPayload: local)]
            }
        }

        let merged = "<<<<<<< Local\n\(local)\n=======\n\(server)\n>>>>>>> Server"
        return [
            MergeSuggestion(strategy: .keepLocal, preview: "Keep local version.", mergedPayload: local),
            MergeSuggestion(strategy: .keepServer, preview: "Keep server version.", mergedPayload: server),
            MergeSuggestion(strategy: .autoMerge, preview: "Manual merge required.", mergedPayload: merged)
        ]
    }
}

public struct SyncOutcome: Codable, Equatable {
    public let resolved: SyncRecord
    public let conflictCopies: [SyncRecord]
    public let suggestions: [MergeSuggestion]
    public let diff: TextDiff
    public let historyEntries: [HistoryEntry]
}

public final class SyncEngine {
    private let diffEngine: DiffEngine
    private let resolver: ConflictResolver
    private let telemetry: TelemetrySink

    public init(
        diffEngine: DiffEngine = LineDiffEngine(),
        resolver: ConflictResolver = RuleBasedConflictResolver(),
        telemetry: TelemetrySink = NoopTelemetrySink()
    ) {
        self.diffEngine = diffEngine
        self.resolver = resolver
        self.telemetry = telemetry
    }

    public func applyLocalChange(record: SyncRecord, newPayload: String, author: String) -> (SyncRecord, HistoryEntry) {
        let nextRevision = Revision(version: record.revision.version + 1, author: author)
        let history = HistoryEntry(recordId: record.id, previousPayload: record.payload, revision: record.revision)
        let updated = SyncRecord(id: record.id, revision: nextRevision, payload: newPayload)
        return (updated, history)
    }

    public func rollback(record: SyncRecord, history: HistoryEntry, author: String) -> SyncRecord {
        let nextRevision = Revision(version: record.revision.version + 1, author: author)
        return SyncRecord(id: record.id, revision: nextRevision, payload: history.previousPayload)
    }

    public func reconcile(local: SyncRecord, server: SyncRecord, base: SyncRecord?) throws -> SyncOutcome {
        if let base, base.revision.version != server.revision.version {
            telemetry.record(.init(name: "sync_occ_conflict", properties: ["id": local.id]))
            throw SyncError.occConflict
        }

        let diff = diffEngine.diff(base: server.payload, updated: local.payload)
        let suggestions = resolver.suggest(local: local.payload, server: server.payload, base: base?.payload)
        var historyEntries: [HistoryEntry] = []

        if local.payload != server.payload {
            historyEntries.append(HistoryEntry(recordId: server.id, previousPayload: server.payload, revision: server.revision))
        }

        if local.payload == server.payload {
            return SyncOutcome(resolved: server, conflictCopies: [], suggestions: suggestions, diff: diff, historyEntries: historyEntries)
        }

        let conflictId = "\(local.id)-conflict-\(Int(Date().timeIntervalSince1970))"
        let conflictCopy = SyncRecord(id: conflictId, revision: local.revision, payload: local.payload)
        telemetry.record(.init(name: "sync_conflict_copy", properties: ["id": local.id]))

        return SyncOutcome(resolved: server, conflictCopies: [conflictCopy], suggestions: suggestions, diff: diff, historyEntries: historyEntries)
    }
}
