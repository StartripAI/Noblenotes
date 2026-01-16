# SyncKit

## Responsibility
OCC revision handling, diff output, conflict copies, and merge suggestions.

## Dependencies
- CoreKit
- TelemetryKit

## Usage
```swift
let engine = SyncEngine()
let outcome = try engine.reconcile(local: local, server: server, base: base)
let (updated, history) = engine.applyLocalChange(record: local, newPayload: "edit", author: "me")
let rolledBack = engine.rollback(record: updated, history: history, author: "me")

let store = InMemoryKeyValueStore()
let outbox = Outbox(store: KeyValueOutboxStore(store: store), userId: "user")
let server = ServerStub()
let service = SyncService(server: server)
let result = service.sync(userId: "user", localRecords: [:], outbox: outbox, lastSyncToken: 0)
```
