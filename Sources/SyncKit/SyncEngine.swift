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

public final class SyncEngine {
    private let telemetry: TelemetrySink

    public init(telemetry: TelemetrySink = NoopTelemetrySink()) {
        self.telemetry = telemetry
    }

    public func applyLocalChange(record: SyncRecord, newPayload: String, author: String) -> (SyncRecord, HistoryEntry) {
        let nextRevision = Revision(version: record.revision.version + 1, author: author)
        let history = HistoryEntry(recordId: record.id, previousPayload: record.payload, revision: record.revision)
        let updated = SyncRecord(id: record.id, revision: nextRevision, payload: newPayload)
        return (updated, history)
    }

    public func reconcile(local: SyncRecord, server: SyncRecord, base: SyncRecord?) throws -> SyncOutcome {
        if let base, base.revision.version != server.revision.version {
            telemetry.record(.init(name: "sync_occ_conflict", properties: ["id": local.id]))
            throw SyncError.occConflict
        }

        if local.payload == server.payload {
            return SyncOutcome(resolved: server, conflictCopies: [])
        }

        let conflictId = "\(local.id)-conflict-\(Int(Date().timeIntervalSince1970))"
        let conflictCopy = SyncRecord(id: conflictId, revision: local.revision, payload: local.payload)
        telemetry.record(.init(name: "sync_conflict_copy", properties: ["id": local.id]))

        return SyncOutcome(resolved: server, conflictCopies: [conflictCopy])
    }
}

public struct SyncOutcome {
    public let resolved: SyncRecord
    public let conflictCopies: [SyncRecord]
}
