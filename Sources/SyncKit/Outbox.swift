import Foundation
import StorageKit

public enum OutboxOperationKind: String, Codable {
    case create
    case update
    case delete
}

public struct OutboxOperation: Codable, Equatable {
    public let id: String
    public let recordId: String
    public let kind: OutboxOperationKind
    public let payload: String
    public let baseRevisionVersion: Int?

    public init(id: String = UUID().uuidString, recordId: String, kind: OutboxOperationKind, payload: String, baseRevisionVersion: Int?) {
        self.id = id
        self.recordId = recordId
        self.kind = kind
        self.payload = payload
        self.baseRevisionVersion = baseRevisionVersion
    }
}

public protocol OutboxStore {
    func load(userId: String) -> [OutboxOperation]
    func save(userId: String, operations: [OutboxOperation])
}

public final class KeyValueOutboxStore: OutboxStore {
    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    public func load(userId: String) -> [OutboxOperation] {
        store.load(key: key(for: userId)) ?? []
    }

    public func save(userId: String, operations: [OutboxOperation]) {
        store.save(key: key(for: userId), value: operations)
    }

    private func key(for userId: String) -> String {
        "outbox_\(userId)"
    }
}

public final class Outbox {
    private let store: OutboxStore
    private let userId: String

    public init(store: OutboxStore, userId: String) {
        self.store = store
        self.userId = userId
    }

    public func enqueue(_ operation: OutboxOperation) {
        var operations = store.load(userId: userId)
        operations.append(operation)
        store.save(userId: userId, operations: operations)
    }

    public func pending() -> [OutboxOperation] {
        store.load(userId: userId)
    }

    public func replace(with operations: [OutboxOperation]) {
        store.save(userId: userId, operations: operations)
    }
}
