# StorageKit

## Responsibility
Lightweight persistence abstractions for future SQLite/SwiftData/Cloud backends.

## Dependencies
- CoreKit

## Usage
```swift
let store = InMemoryKeyValueStore()
store.save(key: "config", value: ["flag": true])
```

```swift
let kv = InMemoryKeyValueStore()
let indexStore = KeyValueHandwritingIndexStore(store: kv)
let index = HandwritingIndex(store: indexStore)
index.upsert(entry: HandwritingIndexEntry(pageId: "page", spans: []))
```
