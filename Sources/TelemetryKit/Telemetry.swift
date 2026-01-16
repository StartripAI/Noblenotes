import Foundation
import CoreKit

public struct TelemetryEvent: Codable, Equatable {
    public let name: String
    public let properties: [String: String]
    public let timestamp: ISO8601Timestamp

    public init(name: String, properties: [String: String], timestamp: ISO8601Timestamp = ISO8601Timestamp()) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

public protocol TelemetrySink {
    func record(_ event: TelemetryEvent)
}

public final class NoopTelemetrySink: TelemetrySink {
    public init() {}

    public func record(_ event: TelemetryEvent) {}
}
