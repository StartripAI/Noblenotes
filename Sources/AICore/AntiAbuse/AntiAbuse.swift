import Foundation
import StorageKit

public enum IntegrityStatus: String, Codable {
    case verified
    case failed
}

public protocol DeviceCheckValidating {
    func validate(deviceId: String) async -> IntegrityStatus
}

public protocol AppAttestValidating {
    func validate(deviceId: String) async -> IntegrityStatus
}

public struct StubDeviceCheckValidator: DeviceCheckValidating {
    public init() {}

    public func validate(deviceId: String) async -> IntegrityStatus {
        .verified
    }
}

public struct StubAppAttestValidator: AppAttestValidating {
    public init() {}

    public func validate(deviceId: String) async -> IntegrityStatus {
        .verified
    }
}

public struct IntegrityValidator {
    private let deviceCheck: DeviceCheckValidating
    private let appAttest: AppAttestValidating

    public init(deviceCheck: DeviceCheckValidating, appAttest: AppAttestValidating) {
        self.deviceCheck = deviceCheck
        self.appAttest = appAttest
    }

    public func verify(deviceId: String) async -> IntegrityStatus {
        let dc = await deviceCheck.validate(deviceId: deviceId)
        let aa = await appAttest.validate(deviceId: deviceId)
        return (dc == .verified && aa == .verified) ? .verified : .failed
    }
}

public protocol TrialClaimStore {
    func load() -> TrialClaimLedger
    func save(_ ledger: TrialClaimLedger)
}

public struct TrialClaimLedger: Codable, Equatable {
    public var claimedDeviceIds: Set<String>

    public init(claimedDeviceIds: Set<String> = []) {
        self.claimedDeviceIds = claimedDeviceIds
    }
}

public final class KeyValueTrialClaimStore: TrialClaimStore {
    private let store: KeyValueStore
    private let key = "trial_claims"

    public init(store: KeyValueStore) {
        self.store = store
    }

    public func load() -> TrialClaimLedger {
        store.load(key: key) ?? TrialClaimLedger()
    }

    public func save(_ ledger: TrialClaimLedger) {
        store.save(key: key, value: ledger)
    }
}

public final class TrialClaimService {
    private let store: TrialClaimStore

    public init(store: TrialClaimStore) {
        self.store = store
    }

    public func claim(deviceId: String) -> Bool {
        var ledger = store.load()
        if ledger.claimedDeviceIds.contains(deviceId) {
            return false
        }
        ledger.claimedDeviceIds.insert(deviceId)
        store.save(ledger)
        return true
    }
}

public protocol AntiAbuseValidator {
    func validate(deviceId: String) async -> Bool
}

public struct AntiAbuseStub: AntiAbuseValidator {
    public init() {}

    public func validate(deviceId: String) async -> Bool {
        true
    }
}
