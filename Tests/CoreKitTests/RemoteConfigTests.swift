import XCTest
@testable import CoreKit

final class RemoteConfigTests: XCTestCase {
    func testDefaultLoad() throws {
        let dir = try makeTempConfig(defaultJSON: defaultConfigJSON)
        let loader = RemoteConfigLoader(configDirectory: dir)
        let config = loader.load()
        XCTAssertEqual(config.trialProfile, .conservative)
        XCTAssertEqual(config.regionPolicy, .nonCn)
        XCTAssertEqual(config.killSwitchCloudAI, false)
        XCTAssertEqual(config.budgetGateMode, .tighten)
    }

    func testOverrideLoad() throws {
        let dir = try makeTempConfig(defaultJSON: defaultConfigJSON, overrideJSON: overrideConfigJSON)
        let loader = RemoteConfigLoader(configDirectory: dir)
        let config = loader.load()
        XCTAssertEqual(config.trialProfile, .moderate)
        XCTAssertEqual(config.regionPolicy, .cn)
        XCTAssertEqual(config.killSwitchCloudAI, true)
        XCTAssertEqual(config.budgetGateMode, .disableCloud)
    }

    func testInvalidConfigFallsBack() throws {
        let dir = try makeTempConfig(defaultJSON: "{ invalid json }")
        let loader = RemoteConfigLoader(configDirectory: dir)
        let config = loader.load()
        XCTAssertEqual(config, .default)
    }

    private var defaultConfigJSON: String {
        """
        {
          \"trial_profile\": \"conservative\",
          \"region_policy\": \"NonCN\",
          \"kill_switch_cloud_ai\": false,
          \"budget_gate_mode\": \"tighten\"
        }
        """
    }

    private var overrideConfigJSON: String {
        """
        {
          \"trial_profile\": \"moderate\",
          \"region_policy\": \"CN\",
          \"kill_switch_cloud_ai\": true,
          \"budget_gate_mode\": \"disable_cloud\"
        }
        """
    }

    private func makeTempConfig(defaultJSON: String, overrideJSON: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaultURL = dir.appendingPathComponent("default.json")
        try defaultJSON.data(using: .utf8)?.write(to: defaultURL)
        if let overrideJSON {
            let overrideURL = dir.appendingPathComponent("override.json")
            try overrideJSON.data(using: .utf8)?.write(to: overrideURL)
        }
        return dir
    }
}
