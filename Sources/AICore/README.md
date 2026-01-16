# AICore

## Responsibility
Provider routing, anti-abuse hooks, and AI request/response types.

## Dependencies
- CoreKit
- QuotaKit
- TelemetryKit

## Usage
```swift
let router = ProviderRouter(
  onDeviceProvider: LocalProvider(capabilities: .init(supportsOffline: true, supportsChinese: true, maxContextTokens: 4096)),
  cloudProvider: CloudProvider(capabilities: .init(supportsOffline: false, supportsChinese: true, maxContextTokens: 128000)),
  capabilityGate: CapabilityGate(),
  config: StaticRemoteConfig(
    cn: .init(preferOnDevice: false, allowOnDeviceLightTasksInCn: true),
    nonCn: .init(preferOnDevice: true, allowOnDeviceLightTasksInCn: true)
  ),
  quotaManager: QuotaManager(store: InMemoryQuotaStore(), policyProvider: { policy })
)
let routed = try await router.route(request: request, region: .cnMainland, deviceIdHash: "device")
let response = try await routed.provider.generate(request)
await routed.lease.release()
```
