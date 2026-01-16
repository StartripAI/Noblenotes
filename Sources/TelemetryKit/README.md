# TelemetryKit

## Responsibility
Minimal telemetry event types and sinks used by Core services.

## Dependencies
- CoreKit

## Usage
```swift
let sink = NoopTelemetrySink()
sink.record(.init(name: "boot", properties: [:]))
```
