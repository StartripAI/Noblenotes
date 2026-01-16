# QuotaKit

## Responsibility
CN/Non-CN token budgets, rate limits, concurrency gates, and global budget kill switch.

## Dependencies
- CoreKit
- TelemetryKit

## Usage
```swift
let manager = QuotaManager(store: InMemoryQuotaStore(), policyProvider: { policy })
let lease = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 10, estimatedTout: 5, estimatedContextTokens: 100)
await lease.release()
```
