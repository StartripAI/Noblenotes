# CoreKit

## Responsibility
Core domain primitives and runtime capability gating used by all modules.

## Dependencies
None.

## Usage
```swift
let gate = CapabilityGate()
let available = gate.onDeviceAIAvailable(for: Locale(identifier: "zh-CN"))
```
