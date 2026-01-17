import XCTest
@testable import SyncKit
import StorageKit

final class SyncServiceTests: XCTestCase {
    func testOfflineEditsPushToServer() {
        let store = InMemoryKeyValueStore()
        let outbox = Outbox(store: KeyValueOutboxStore(store: store), userId: "user")
        let server = ServerStub()
        let service = SyncService(server: server)

        outbox.enqueue(OutboxOperation(recordId: "note-1", kind: .create, payload: "hello", baseRevisionVersion: nil))
        let result = service.sync(userId: "user", localRecords: [:], outbox: outbox, lastSyncToken: 0)

        XCTAssertEqual(result.localRecords["note-1"]?.payload, "hello")
        XCTAssertEqual(server.record(userId: "user", id: "note-1")?.payload, "hello")
        XCTAssertTrue(outbox.pending().isEmpty)
    }

    func testConcurrentRemoteEditCreatesConflictCopy() {
        let store = InMemoryKeyValueStore()
        let outbox = Outbox(store: KeyValueOutboxStore(store: store), userId: "user")
        let server = ServerStub()
        let service = SyncService(server: server)

        let serverRecord = SyncRecord(id: "note-1", revision: Revision(version: 2, author: "server"), payload: "remote")
        server.seed(userId: "user", record: serverRecord)

        let localRecord = SyncRecord(id: "note-1", revision: Revision(version: 1, author: "user"), payload: "local")
        outbox.enqueue(OutboxOperation(recordId: "note-1", kind: .update, payload: "local", baseRevisionVersion: 1))

        let result = service.sync(userId: "user", localRecords: ["note-1": localRecord], outbox: outbox, lastSyncToken: 0)

        XCTAssertFalse(result.conflictCopies.isEmpty)
        XCTAssertFalse(outbox.pending().isEmpty)
        XCTAssertEqual(result.localRecords["note-1"]?.payload, "remote")
    }

    func testPullBringsRemoteOnlyNote() {
        let store = InMemoryKeyValueStore()
        let outbox = Outbox(store: KeyValueOutboxStore(store: store), userId: "user")
        let server = ServerStub()
        let service = SyncService(server: server)

        let serverRecord = SyncRecord(id: "note-2", revision: Revision(version: 1, author: "server"), payload: "remote-only")
        server.seed(userId: "user", record: serverRecord)

        let result = service.sync(userId: "user", localRecords: [:], outbox: outbox, lastSyncToken: 0)
        XCTAssertEqual(result.localRecords["note-2"]?.payload, "remote-only")
        XCTAssertEqual(result.appliedRemoteChanges.count, 1)
    }
}
