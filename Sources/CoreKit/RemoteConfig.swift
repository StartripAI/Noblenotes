import Foundation

public enum TrialProfileSetting: String, Codable {
    case conservative
    case moderate
}

public enum RegionPolicySetting: String, Codable {
    case cn = "CN"
    case nonCn = "NonCN"
}

public enum BudgetGateMode: String, Codable {
    case tighten
    case disableCloud = "disable_cloud"
}

public struct RemoteConfig: Codable, Equatable {
    public let trialProfile: TrialProfileSetting
    public let regionPolicy: RegionPolicySetting
    public let killSwitchCloudAI: Bool
    public let budgetGateMode: BudgetGateMode

    public init(trialProfile: TrialProfileSetting, regionPolicy: RegionPolicySetting, killSwitchCloudAI: Bool, budgetGateMode: BudgetGateMode) {
        self.trialProfile = trialProfile
        self.regionPolicy = regionPolicy
        self.killSwitchCloudAI = killSwitchCloudAI
        self.budgetGateMode = budgetGateMode
    }

    public static let `default` = RemoteConfig(
        trialProfile: .conservative,
        regionPolicy: .nonCn,
        killSwitchCloudAI: false,
        budgetGateMode: .tighten
    )

    private enum CodingKeys: String, CodingKey {
        case trialProfile = "trial_profile"
        case regionPolicy = "region_policy"
        case killSwitchCloudAI = "kill_switch_cloud_ai"
        case budgetGateMode = "budget_gate_mode"
    }
}

public final class RemoteConfigLoader {
    private let configDirectory: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(configDirectory: URL = URL(fileURLWithPath: "Config", isDirectory: true), fileManager: FileManager = .default) {
        self.configDirectory = configDirectory
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
    }

    public func load() -> RemoteConfig {
        guard let defaultConfig = loadConfig(named: "default.json") else {
            return .default
        }
        guard let overrideConfig = loadConfig(named: "override.json") else {
            return defaultConfig
        }
        return overrideConfig
    }

    private func loadConfig(named name: String) -> RemoteConfig? {
        let url = configDirectory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(RemoteConfig.self, from: data)
    }
}
