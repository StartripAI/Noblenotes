import XCTest
@testable import AICore
import StorageKit

final class AntiAbuseTests: XCTestCase {
    func testTrialClaimOncePerDevice() {
        let store = InMemoryKeyValueStore()
        let claimStore = KeyValueTrialClaimStore(store: store)
        let service = TrialClaimService(store: claimStore)

        XCTAssertTrue(service.claim(deviceId: "device-1"))
        XCTAssertFalse(service.claim(deviceId: "device-1"))
    }
}
