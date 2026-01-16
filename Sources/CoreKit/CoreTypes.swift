import Foundation

public enum Region: String, Codable {
    case cnMainland
    case nonCn
}

public protocol JSONValue: Codable {}

public struct ISO8601Timestamp: Codable, Equatable, Hashable {
    public let date: Date

    public init(_ date: Date = Date()) {
        self.date = date
    }
}

public protocol CapabilityProbe {
    func isOnDeviceAIAvailable(for locale: Locale) -> Bool
}

public struct DefaultCapabilityProbe: CapabilityProbe {
    public init() {}

    public func isOnDeviceAIAvailable(for locale: Locale) -> Bool {
        #if canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }
}

public final class CapabilityGate {
    private let probe: CapabilityProbe

    public init(probe: CapabilityProbe = DefaultCapabilityProbe()) {
        self.probe = probe
    }

    public func onDeviceAIAvailable(for locale: Locale) -> Bool {
        probe.isOnDeviceAIAvailable(for: locale)
    }
}
