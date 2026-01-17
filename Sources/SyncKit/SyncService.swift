import Foundation

public struct SyncResult: Codable, Equatable {
    public let localRecords: [String: SyncRecord]
    public let conflictCopies: [SyncRecord]
    public let appliedRemoteChanges: [SyncRecord]
    public let newSyncToken: Int

    public init(localRecords: [String: SyncRecord], conflictCopies: [SyncRecord], appliedRemoteChanges: [SyncRecord], newSyncToken: Int) {
        self.localRecords = localRecords
        self.conflictCopies = conflictCopies
        self.appliedRemoteChanges = appliedRemoteChanges
        self.newSyncToken = newSyncToken
    }
}

public final class SyncService {
    private let engine: SyncEngine
    private let server: ServerStub

    public init(engine: SyncEngine = SyncEngine(), server: ServerStub) {
        self.engine = engine
        self.server = server
    }

    public func sync(
        userId: String,
        localRecords: [String: SyncRecord],
        outbox: Outbox,
        lastSyncToken: Int
    ) -> SyncResult {
        var local = localRecords
        var conflictCopies: [SyncRecord] = []
        var remainingOps: [OutboxOperation] = []

        for operation in outbox.pending() {
            switch server.apply(userId: userId, operation: operation) {
            case .success(let record):
                local[record.id] = record
            case .failure:
                let conflictPayload = local[operation.recordId]?.payload ?? operation.payload
                let conflictId = "\(operation.recordId)-conflict-\(Int(Date().timeIntervalSince1970))"
                let conflict = SyncRecord(
                    id: conflictId,
                    revision: Revision(version: 1, author: userId),
                    payload: conflictPayload
                )
                conflictCopies.append(conflict)
                remainingOps.append(operation)
            }
        }

        outbox.replace(with: remainingOps)

        let (remoteChanges, newToken) = server.pull(userId: userId, since: lastSyncToken)
        var appliedRemote: [SyncRecord] = []
        for change in remoteChanges {
            if let localRecord = local[change.id], localRecord.payload != change.payload {
                let conflictId = "\(change.id)-conflict-\(Int(Date().timeIntervalSince1970))"
                let conflict = SyncRecord(id: conflictId, revision: localRecord.revision, payload: localRecord.payload)
                conflictCopies.append(conflict)
            }
            local[change.id] = change
            appliedRemote.append(change)
        }

        return SyncResult(
            localRecords: local,
            conflictCopies: conflictCopies,
            appliedRemoteChanges: appliedRemote,
            newSyncToken: newToken
        )
    }
}
