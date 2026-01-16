import Foundation
import CoreKit
import QuotaKit
import TelemetryKit

public enum AIProviderKind: String, Codable {
    case onDevice
    case cloud
    case noop
}

public struct AIProviderCapabilities: Codable, Equatable {
    public let supportsOffline: Bool
    public let supportsChinese: Bool
    public let maxContextTokens: Int

    public init(supportsOffline: Bool, supportsChinese: Bool, maxContextTokens: Int) {
        self.supportsOffline = supportsOffline
        self.supportsChinese = supportsChinese
        self.maxContextTokens = maxContextTokens
    }
}

public struct AITask: Codable, Equatable {
    public enum Kind: String, Codable {
        case summary
        case flashcards
        case quiz
        case rewrite
        case mergeSuggestion
        case citations
    }

    public let kind: Kind
    public let requiresCitations: Bool
    public let minContextTokens: Int

    public init(kind: Kind, requiresCitations: Bool, minContextTokens: Int) {
        self.kind = kind
        self.requiresCitations = requiresCitations
        self.minContextTokens = minContextTokens
    }

    public var isLightweight: Bool {
        switch kind {
        case .summary, .flashcards, .quiz, .rewrite, .mergeSuggestion:
            return !requiresCitations
        case .citations:
            return false
        }
    }
}

public struct AIRequest: Codable, Equatable {
    public let task: AITask
    public let localeIdentifier: String
    public let input: String
    public let estimatedTin: Int
    public let estimatedTout: Int
    public let estimatedContextTokens: Int

    public init(task: AITask, localeIdentifier: String, input: String, estimatedTin: Int, estimatedTout: Int, estimatedContextTokens: Int) {
        self.task = task
        self.localeIdentifier = localeIdentifier
        self.input = input
        self.estimatedTin = estimatedTin
        self.estimatedTout = estimatedTout
        self.estimatedContextTokens = estimatedContextTokens
    }
}

public struct AIResponse: Codable, Equatable {
    public let output: String
    public let provider: AIProviderKind

    public init(output: String, provider: AIProviderKind) {
        self.output = output
        self.provider = provider
    }
}

public protocol AIProvider {
    var kind: AIProviderKind { get }
    var capabilities: AIProviderCapabilities { get }
    func generate(_ req: AIRequest) async throws -> AIResponse
}

public final class LocalProvider: AIProvider {
    public let kind: AIProviderKind = .onDevice
    public let capabilities: AIProviderCapabilities

    public init(capabilities: AIProviderCapabilities) {
        self.capabilities = capabilities
    }

    public func generate(_ req: AIRequest) async throws -> AIResponse {
        AIResponse(output: "local:\(req.input)", provider: kind)
    }
}

public final class CloudProvider: AIProvider {
    public let kind: AIProviderKind = .cloud
    public let capabilities: AIProviderCapabilities

    public init(capabilities: AIProviderCapabilities) {
        self.capabilities = capabilities
    }

    public func generate(_ req: AIRequest) async throws -> AIResponse {
        AIResponse(output: "cloud:\(req.input)", provider: kind)
    }
}

public final class NoopProvider: AIProvider {
    public let kind: AIProviderKind = .noop
    public let capabilities: AIProviderCapabilities = AIProviderCapabilities(supportsOffline: true, supportsChinese: true, maxContextTokens: 0)

    public init() {}

    public func generate(_ req: AIRequest) async throws -> AIResponse {
        AIResponse(output: "noop", provider: kind)
    }
}

public struct RegionRoutingPolicy: Codable, Equatable {
    public let preferOnDevice: Bool
    public let allowOnDeviceLightTasksInCn: Bool

    public init(preferOnDevice: Bool, allowOnDeviceLightTasksInCn: Bool) {
        self.preferOnDevice = preferOnDevice
        self.allowOnDeviceLightTasksInCn = allowOnDeviceLightTasksInCn
    }
}

public protocol RemoteConfigProviding {
    func policy(for region: Region) -> RegionRoutingPolicy
}

public struct StaticRemoteConfig: RemoteConfigProviding {
    private let cn: RegionRoutingPolicy
    private let nonCn: RegionRoutingPolicy

    public init(cn: RegionRoutingPolicy, nonCn: RegionRoutingPolicy) {
        self.cn = cn
        self.nonCn = nonCn
    }

    public func policy(for region: Region) -> RegionRoutingPolicy {
        region == .cnMainland ? cn : nonCn
    }
}

public struct ConfigBackedRemoteConfig: RemoteConfigProviding {
    private let loader: RemoteConfigLoader

    public init(loader: RemoteConfigLoader = RemoteConfigLoader()) {
        self.loader = loader
    }

    public func policy(for region: Region) -> RegionRoutingPolicy {
        let config = loader.load()
        let isCn = config.regionPolicy == .cn || region == .cnMainland
        if isCn {
            return RegionRoutingPolicy(preferOnDevice: false, allowOnDeviceLightTasksInCn: true)
        }
        return RegionRoutingPolicy(preferOnDevice: true, allowOnDeviceLightTasksInCn: true)
    }
}

public struct RoutedProvider {
    public let provider: AIProvider
    public let lease: QuotaLease
}

public final class ProviderRouter {
    private let onDeviceProvider: AIProvider?
    private let cloudProvider: AIProvider
    private let capabilityGate: CapabilityGate
    private let config: RemoteConfigProviding
    private let quotaManager: QuotaManager
    private let telemetry: TelemetrySink

    public init(
        onDeviceProvider: AIProvider?,
        cloudProvider: AIProvider,
        capabilityGate: CapabilityGate,
        config: RemoteConfigProviding = ConfigBackedRemoteConfig(),
        quotaManager: QuotaManager,
        telemetry: TelemetrySink = NoopTelemetrySink()
    ) {
        self.onDeviceProvider = onDeviceProvider
        self.cloudProvider = cloudProvider
        self.capabilityGate = capabilityGate
        self.config = config
        self.quotaManager = quotaManager
        self.telemetry = telemetry
    }

    public func route(request: AIRequest, region: Region, deviceIdHash: String) async throws -> RoutedProvider {
        let policy = config.policy(for: region)
        let locale = Locale(identifier: request.localeIdentifier)
        let onDeviceAvailable = capabilityGate.onDeviceAIAvailable(for: locale)
        let onDeviceCaps = onDeviceProvider?.capabilities
        let isShortContext = request.estimatedContextTokens <= (onDeviceCaps?.maxContextTokens ?? 0)
        let useOnDevice: Bool

        switch region {
        case .nonCn:
            useOnDevice = policy.preferOnDevice && onDeviceAvailable && onDeviceProvider != nil && isShortContext
        case .cnMainland:
            useOnDevice = policy.allowOnDeviceLightTasksInCn && onDeviceAvailable && onDeviceProvider != nil && request.task.isLightweight && isShortContext
        }

        let lease = try await quotaManager.authorize(
            deviceIdHash: deviceIdHash,
            estimatedTin: request.estimatedTin,
            estimatedTout: request.estimatedTout,
            estimatedContextTokens: request.estimatedContextTokens
        )

        if useOnDevice {
            telemetry.record(.init(name: "provider_on_device", properties: ["region": region.rawValue]))
            return RoutedProvider(provider: onDeviceProvider!, lease: lease)
        }

        telemetry.record(.init(name: "provider_cloud", properties: ["region": region.rawValue]))
        return RoutedProvider(provider: cloudProvider, lease: lease)
    }
}
