import XCTest
@testable import AICore
import QuotaKit
import CoreKit
import StorageKit

final class FraudSimulatorTests: XCTestCase {
    func testBudgetGateTightensUnderSpam() async {
        let policy = QuotaPolicy(
            region: .nonCn,
            profile: .conservative,
            tinPerDay: 100000,
            toutPerDay: 100000,
            reqPerMinute: 1000,
            maxConcurrency: 100,
            maxTinPerRequest: 1000,
            maxToutPerRequest: 1000,
            maxContextTokens: 1000,
            dailyGlobalBudgetUsd: 0.01,
            killSwitchEnabled: false,
            usdPerTinToken: 0.001,
            usdPerToutToken: 0.001
        )
        let catalog = QuotaPolicyCatalog(
            cnConservative: policy,
            cnModerate: policy,
            nonCnConservative: policy,
            nonCnModerate: policy
        )
        let configDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let configJSON = """
            {
              \"trial_profile\": \"conservative\",
              \"region_policy\": \"NonCN\",
              \"kill_switch_cloud_ai\": false,
              \"budget_gate_mode\": \"tighten\"
            }
            """
            try configJSON.data(using: .utf8)?.write(to: configDir.appendingPathComponent("default.json"))
        } catch {
            XCTFail("Failed to write config: \(error)")
        }
        let loader = RemoteConfigLoader(configDirectory: configDir)
        let provider = ConfigBackedQuotaPolicyProvider(loader: loader, catalog: catalog)
        let manager = QuotaManager(store: InMemoryQuotaStore(), policyProvider: provider)

        let claimService = TrialClaimService(store: KeyValueTrialClaimStore(store: InMemoryKeyValueStore()))
        let simulator = FraudSimulator(quotaManager: manager, claimService: claimService)
        let result = await simulator.simulate(deviceCount: 10_000, requestsPerDevice: 2, estimatedTin: 100, estimatedTout: 100, estimatedContextTokens: 100)

        XCTAssertGreaterThan(result.budgetGateTriggered, 0)
    }

    func testKillSwitchStopsCloudSpend() async {
        let policy = QuotaPolicy(
            region: .nonCn,
            profile: .conservative,
            tinPerDay: 100000,
            toutPerDay: 100000,
            reqPerMinute: 1000,
            maxConcurrency: 100,
            maxTinPerRequest: 1000,
            maxToutPerRequest: 1000,
            maxContextTokens: 1000,
            dailyGlobalBudgetUsd: 1.0,
            killSwitchEnabled: true,
            usdPerTinToken: 0.001,
            usdPerToutToken: 0.001
        )
        let catalog = QuotaPolicyCatalog(
            cnConservative: policy,
            cnModerate: policy,
            nonCnConservative: policy,
            nonCnModerate: policy
        )
        let configDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let configJSON = """
            {
              \"trial_profile\": \"conservative\",
              \"region_policy\": \"NonCN\",
              \"kill_switch_cloud_ai\": true,
              \"budget_gate_mode\": \"tighten\"
            }
            """
            try configJSON.data(using: .utf8)?.write(to: configDir.appendingPathComponent("default.json"))
        } catch {
            XCTFail("Failed to write config: \(error)")
        }
        let loader = RemoteConfigLoader(configDirectory: configDir)
        let provider = ConfigBackedQuotaPolicyProvider(loader: loader, catalog: catalog)
        let manager = QuotaManager(store: InMemoryQuotaStore(), policyProvider: provider)

        let claimService = TrialClaimService(store: KeyValueTrialClaimStore(store: InMemoryKeyValueStore()))
        let simulator = FraudSimulator(quotaManager: manager, claimService: claimService)
        let result = await simulator.simulate(deviceCount: 10_000, requestsPerDevice: 1, estimatedTin: 10, estimatedTout: 10, estimatedContextTokens: 10)

        XCTAssertGreaterThan(result.killSwitchTriggered, 0)
    }
}
