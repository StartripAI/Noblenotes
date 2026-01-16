import XCTest
@testable import AICore
import QuotaKit
import CoreKit

final class ProviderRouterTests: XCTestCase {
    struct FixedProbe: CapabilityProbe {
        let available: Bool
        func isOnDeviceAIAvailable(for locale: Locale) -> Bool { available }
    }

    func testNonCnShortTaskUsesOnDevice() async throws {
        let onDevice = LocalProvider(capabilities: .init(supportsOffline: true, supportsChinese: true, maxContextTokens: 4096))
        let cloud = CloudProvider(capabilities: .init(supportsOffline: false, supportsChinese: true, maxContextTokens: 128000))
        let router = ProviderRouter(
            onDeviceProvider: onDevice,
            cloudProvider: cloud,
            capabilityGate: CapabilityGate(probe: FixedProbe(available: true)),
            config: StaticRemoteConfig(
                cn: .init(preferOnDevice: false, allowOnDeviceLightTasksInCn: true),
                nonCn: .init(preferOnDevice: true, allowOnDeviceLightTasksInCn: true)
            ),
            quotaManager: QuotaManager(store: InMemoryQuotaStore(), policyProvider: {
                QuotaPolicy(region: .nonCn, profile: .conservative, tinPerDay: 100, toutPerDay: 50, reqPerMinute: 10, maxConcurrency: 5, maxTinPerRequest: 50, maxToutPerRequest: 25, maxContextTokens: 4000, dailyGlobalBudgetUsd: 1.0, killSwitchEnabled: false, usdPerTinToken: 0.001, usdPerToutToken: 0.002)
            })
        )

        let request = AIRequest(
            task: AITask(kind: .summary, requiresCitations: false, minContextTokens: 512),
            localeIdentifier: "en-US",
            input: "test",
            estimatedTin: 10,
            estimatedTout: 5,
            estimatedContextTokens: 512
        )

        let routed = try await router.route(request: request, region: .nonCn, deviceIdHash: "dev")
        XCTAssertEqual(routed.provider.kind, .onDevice)
    }
}
