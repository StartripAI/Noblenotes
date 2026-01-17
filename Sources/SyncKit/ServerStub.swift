import Foundation
import CoreKit

public struct ServerChange: Codable, Equatable {
    public let token: Int
    public let record: SyncRecord

    public init(token: Int, record: SyncRecord) {
        self.token = token
        self.record = record
    }
}

public final class ServerStub {
    private struct UserState {
        var records: [String: SyncRecord] = [:]
        var changes: [ServerChange] = []
        var nextToken: Int = 1
    }

    private var state: [String: UserState] = [:]

    public init() {}

    public func apply(userId: String, operation: OutboxOperation) -> Result<SyncRecord, SyncError> {
        var userState = state[userId] ?? UserState()
        let nowAuthor = "server"
        switch operation.kind {
        case .create:
            if userState.records[operation.recordId] != nil {
                return .failure(.occConflict)
            }
            let record = SyncRecord(id: operation.recordId, revision: Revision(version: 1, author: nowAuthor), payload: operation.payload)
            userState.records[record.id] = record
            appendChange(record, userState: &userState)
            state[userId] = userState
            return .success(record)
        case .update:
            guard let existing = userState.records[operation.recordId] else {
                return .failure(.occConflict)
            }
            guard operation.baseRevisionVersion == existing.revision.version else {
                return .failure(.occConflict)
            }
            let record = SyncRecord(id: existing.id, revision: Revision(version: existing.revision.version + 1, author: nowAuthor), payload: operation.payload)
            userState.records[record.id] = record
            appendChange(record, userState: &userState)
            state[userId] = userState
            return .success(record)
        case .delete:
            guard let existing = userState.records[operation.recordId] else {
                return .failure(.occConflict)
            }
            guard operation.baseRevisionVersion == existing.revision.version else {
                return .failure(.occConflict)
            }
            userState.records[existing.id] = nil
            let tombstone = SyncRecord(id: existing.id, revision: Revision(version: existing.revision.version + 1, author: nowAuthor), payload: "")
            appendChange(tombstone, userState: &userState)
            state[userId] = userState
            return .success(tombstone)
        }
    }

    public func pull(userId: String, since token: Int) -> (changes: [SyncRecord], newToken: Int) {
        let userState = state[userId] ?? UserState()
        let changes = userState.changes.filter { $0.token > token }.map { $0.record }
        let newToken = userState.nextToken - 1
        return (changes, newToken)
    }

    public func record(userId: String, id: String) -> SyncRecord? {
        state[userId]?.records[id]
    }

    public func seed(userId: String, record: SyncRecord) {
        var userState = state[userId] ?? UserState()
        userState.records[record.id] = record
        appendChange(record, userState: &userState)
        state[userId] = userState
    }

    private func appendChange(_ record: SyncRecord, userState: inout UserState) {
        let change = ServerChange(token: userState.nextToken, record: record)
        userState.changes.append(change)
        userState.nextToken += 1
    }
}
