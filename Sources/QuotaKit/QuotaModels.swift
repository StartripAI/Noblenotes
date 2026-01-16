import Foundation
import CoreKit
import TelemetryKit

public enum TrialProfile: String, Codable {
    case conservative
    case moderate
}

public struct QuotaPolicy: Codable, Equatable {
    public let region: Region
    public let profile: TrialProfile
    public let tinPerDay: Int
    public let toutPerDay: Int
    public let reqPerMinute: Int
    public let maxConcurrency: Int
    public let maxTinPerRequest: Int
    public let maxToutPerRequest: Int
    public let maxContextTokens: Int
    public let dailyGlobalBudgetUsd: Double
    public let killSwitchEnabled: Bool
    public let usdPerTinToken: Double
    public let usdPerToutToken: Double

    public init(
        region: Region,
        profile: TrialProfile,
        tinPerDay: Int,
        toutPerDay: Int,
        reqPerMinute: Int,
        maxConcurrency: Int,
        maxTinPerRequest: Int,
        maxToutPerRequest: Int,
        maxContextTokens: Int,
        dailyGlobalBudgetUsd: Double,
        killSwitchEnabled: Bool,
        usdPerTinToken: Double,
        usdPerToutToken: Double
    ) {
        self.region = region
        self.profile = profile
        self.tinPerDay = tinPerDay
        self.toutPerDay = toutPerDay
        self.reqPerMinute = reqPerMinute
        self.maxConcurrency = maxConcurrency
        self.maxTinPerRequest = maxTinPerRequest
        self.maxToutPerRequest = maxToutPerRequest
        self.maxContextTokens = maxContextTokens
        self.dailyGlobalBudgetUsd = dailyGlobalBudgetUsd
        self.killSwitchEnabled = killSwitchEnabled
        self.usdPerTinToken = usdPerTinToken
        self.usdPerToutToken = usdPerToutToken
    }
}

public struct DeviceLedger: Codable, Equatable {
    public var dayKey: String
    public var tinUsed: Int
    public var toutUsed: Int
    public var recentRequests: [Date]
    public var inFlight: Int

    public init(dayKey: String, tinUsed: Int = 0, toutUsed: Int = 0, recentRequests: [Date] = [], inFlight: Int = 0) {
        self.dayKey = dayKey
        self.tinUsed = tinUsed
        self.toutUsed = toutUsed
        self.recentRequests = recentRequests
        self.inFlight = inFlight
    }
}

public struct GlobalLedger: Codable, Equatable {
    public var dayKey: String
    public var usdSpent: Double

    public init(dayKey: String, usdSpent: Double = 0) {
        self.dayKey = dayKey
        self.usdSpent = usdSpent
    }
}

public enum QuotaError: Error, Equatable {
    case killSwitchActive
    case requestTooLarge
    case contextTooLarge
    case dayLimitExceeded
    case rateLimited
    case concurrencyLimited
    case globalBudgetExceeded
}

public struct QuotaLease: Sendable {
    private let onRelease: @Sendable () async -> Void

    public init(onRelease: @escaping @Sendable () async -> Void) {
        self.onRelease = onRelease
    }

    public func release() async {
        await onRelease()
    }
}

public protocol QuotaStore {
    func loadDeviceLedger(deviceIdHash: String) async -> DeviceLedger
    func saveDeviceLedger(deviceIdHash: String, ledger: DeviceLedger) async
    func loadGlobalLedger(dayKey: String) async -> GlobalLedger
    func saveGlobalLedger(dayKey: String, ledger: GlobalLedger) async
}

public protocol DateProviding {
    var now: Date { get }
}

public struct SystemDateProvider: DateProviding {
    public var now: Date { Date() }
    public init() {}
}

public final class InMemoryQuotaStore: QuotaStore {
    private var deviceLedgers: [String: DeviceLedger] = [:]
    private var globalLedgers: [String: GlobalLedger] = [:]

    public init() {}

    public func loadDeviceLedger(deviceIdHash: String) async -> DeviceLedger {
        deviceLedgers[deviceIdHash] ?? DeviceLedger(dayKey: Self.dayKey(from: Date()))
    }

    public func saveDeviceLedger(deviceIdHash: String, ledger: DeviceLedger) async {
        deviceLedgers[deviceIdHash] = ledger
    }

    public func loadGlobalLedger(dayKey: String) async -> GlobalLedger {
        globalLedgers[dayKey] ?? GlobalLedger(dayKey: dayKey)
    }

    public func saveGlobalLedger(dayKey: String, ledger: GlobalLedger) async {
        globalLedgers[dayKey] = ledger
    }

    public static func dayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public final class QuotaManager {
    private let store: QuotaStore
    private let policyProvider: () -> QuotaPolicy
    private let dateProvider: DateProviding
    private let telemetry: TelemetrySink

    public init(
        store: QuotaStore,
        policyProvider: @escaping () -> QuotaPolicy,
        dateProvider: DateProviding = SystemDateProvider(),
        telemetry: TelemetrySink = NoopTelemetrySink()
    ) {
        self.store = store
        self.policyProvider = policyProvider
        self.dateProvider = dateProvider
        self.telemetry = telemetry
    }

    public convenience init(
        store: QuotaStore,
        policyProvider: ConfigBackedQuotaPolicyProvider,
        dateProvider: DateProviding = SystemDateProvider(),
        telemetry: TelemetrySink = NoopTelemetrySink()
    ) {
        self.init(store: store, policyProvider: { policyProvider.policy() }, dateProvider: dateProvider, telemetry: telemetry)
    }

    public func authorize(deviceIdHash: String, estimatedTin: Int, estimatedTout: Int, estimatedContextTokens: Int) async throws -> QuotaLease {
        let policy = policyProvider()
        if policy.killSwitchEnabled {
            telemetry.record(.init(name: "quota_kill_switch", properties: ["region": policy.region.rawValue]))
            throw QuotaError.killSwitchActive
        }

        guard estimatedTin <= policy.maxTinPerRequest, estimatedTout <= policy.maxToutPerRequest else {
            throw QuotaError.requestTooLarge
        }
        guard estimatedContextTokens <= policy.maxContextTokens else {
            throw QuotaError.contextTooLarge
        }

        let dayKey = InMemoryQuotaStore.dayKey(from: dateProvider.now)
        var deviceLedger = await store.loadDeviceLedger(deviceIdHash: deviceIdHash)
        if deviceLedger.dayKey != dayKey {
            deviceLedger = DeviceLedger(dayKey: dayKey)
        }

        let oneMinuteAgo = dateProvider.now.addingTimeInterval(-60)
        deviceLedger.recentRequests = deviceLedger.recentRequests.filter { $0 >= oneMinuteAgo }
        if deviceLedger.recentRequests.count >= policy.reqPerMinute {
            throw QuotaError.rateLimited
        }

        if deviceLedger.inFlight >= policy.maxConcurrency {
            throw QuotaError.concurrencyLimited
        }

        if deviceLedger.tinUsed + estimatedTin > policy.tinPerDay || deviceLedger.toutUsed + estimatedTout > policy.toutPerDay {
            throw QuotaError.dayLimitExceeded
        }

        let cost = (Double(estimatedTin) * policy.usdPerTinToken) + (Double(estimatedTout) * policy.usdPerToutToken)
        var globalLedger = await store.loadGlobalLedger(dayKey: dayKey)
        if globalLedger.usdSpent + cost > policy.dailyGlobalBudgetUsd {
            throw QuotaError.globalBudgetExceeded
        }

        deviceLedger.tinUsed += estimatedTin
        deviceLedger.toutUsed += estimatedTout
        deviceLedger.recentRequests.append(dateProvider.now)
        deviceLedger.inFlight += 1
        await store.saveDeviceLedger(deviceIdHash: deviceIdHash, ledger: deviceLedger)

        globalLedger.usdSpent += cost
        await store.saveGlobalLedger(dayKey: dayKey, ledger: globalLedger)

        telemetry.record(.init(name: "quota_authorized", properties: [
            "region": policy.region.rawValue,
            "profile": policy.profile.rawValue,
            "tin": String(estimatedTin),
            "tout": String(estimatedTout)
        ]))

        return QuotaLease { [store, dateProvider] in
            var updatedLedger = await store.loadDeviceLedger(deviceIdHash: deviceIdHash)
            if updatedLedger.dayKey != dayKey {
                updatedLedger = DeviceLedger(dayKey: InMemoryQuotaStore.dayKey(from: dateProvider.now))
            }
            updatedLedger.inFlight = max(0, updatedLedger.inFlight - 1)
            await store.saveDeviceLedger(deviceIdHash: deviceIdHash, ledger: updatedLedger)
        }
    }
}

public struct QuotaPolicyCatalog {
    public let cnConservative: QuotaPolicy
    public let cnModerate: QuotaPolicy
    public let nonCnConservative: QuotaPolicy
    public let nonCnModerate: QuotaPolicy

    public init(cnConservative: QuotaPolicy, cnModerate: QuotaPolicy, nonCnConservative: QuotaPolicy, nonCnModerate: QuotaPolicy) {
        self.cnConservative = cnConservative
        self.cnModerate = cnModerate
        self.nonCnConservative = nonCnConservative
        self.nonCnModerate = nonCnModerate
    }

    public func policy(for config: RemoteConfig) -> QuotaPolicy {
        let region = config.regionPolicy == .cn ? Region.cnMainland : Region.nonCn
        let profile: TrialProfile = config.trialProfile == .moderate ? .moderate : .conservative
        let basePolicy: QuotaPolicy
        switch (region, profile) {
        case (.cnMainland, .conservative):
            basePolicy = cnConservative
        case (.cnMainland, .moderate):
            basePolicy = cnModerate
        case (.nonCn, .conservative):
            basePolicy = nonCnConservative
        case (.nonCn, .moderate):
            basePolicy = nonCnModerate
        }

        let adjustedBudget: Double
        switch config.budgetGateMode {
        case .tighten:
            adjustedBudget = basePolicy.dailyGlobalBudgetUsd * 0.5
        case .disableCloud:
            adjustedBudget = 0
        }

        return QuotaPolicy(
            region: basePolicy.region,
            profile: basePolicy.profile,
            tinPerDay: basePolicy.tinPerDay,
            toutPerDay: basePolicy.toutPerDay,
            reqPerMinute: basePolicy.reqPerMinute,
            maxConcurrency: basePolicy.maxConcurrency,
            maxTinPerRequest: basePolicy.maxTinPerRequest,
            maxToutPerRequest: basePolicy.maxToutPerRequest,
            maxContextTokens: basePolicy.maxContextTokens,
            dailyGlobalBudgetUsd: adjustedBudget,
            killSwitchEnabled: config.killSwitchCloudAI,
            usdPerTinToken: basePolicy.usdPerTinToken,
            usdPerToutToken: basePolicy.usdPerToutToken
        )
    }
}

public struct ConfigBackedQuotaPolicyProvider {
    private let loader: RemoteConfigLoader
    private let catalog: QuotaPolicyCatalog

    public init(loader: RemoteConfigLoader = RemoteConfigLoader(), catalog: QuotaPolicyCatalog) {
        self.loader = loader
        self.catalog = catalog
    }

    public func policy() -> QuotaPolicy {
        let config = loader.load()
        return catalog.policy(for: config)
    }
}
