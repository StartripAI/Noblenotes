import XCTest
@testable import QuotaKit
import CoreKit

final class QuotaManagerTests: XCTestCase {
    struct FixedDateProvider: DateProviding {
        var now: Date
    }

    func makePolicy(region: Region, profile: TrialProfile) -> QuotaPolicy {
        QuotaPolicy(
            region: region,
            profile: profile,
            tinPerDay: profile == .conservative ? 100 : 200,
            toutPerDay: profile == .conservative ? 50 : 100,
            reqPerMinute: 2,
            maxConcurrency: 1,
            maxTinPerRequest: 80,
            maxToutPerRequest: 40,
            maxContextTokens: 2000,
            dailyGlobalBudgetUsd: 1.0,
            killSwitchEnabled: false,
            usdPerTinToken: 0.001,
            usdPerToutToken: 0.002
        )
    }

    func testQuotaDeduction() async throws {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = QuotaManager(
            store: store,
            policyProvider: { self.makePolicy(region: .cnMainland, profile: .conservative) },
            dateProvider: FixedDateProvider(now: date)
        )

        let lease = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 20, estimatedTout: 10, estimatedContextTokens: 100)
        await lease.release()

        let ledger = await store.loadDeviceLedger(deviceIdHash: "dev")
        XCTAssertEqual(ledger.tinUsed, 20)
        XCTAssertEqual(ledger.toutUsed, 10)
        XCTAssertEqual(ledger.inFlight, 0)
    }

    func testRateLimit() async {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = QuotaManager(
            store: store,
            policyProvider: { self.makePolicy(region: .cnMainland, profile: .conservative) },
            dateProvider: FixedDateProvider(now: date)
        )

        if let lease = try? await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 10) {
            await lease.release()
        }
        if let lease = try? await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 10) {
            await lease.release()
        }

        do {
            _ = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 10)
            XCTFail("Expected rate limit error")
        } catch let error as QuotaError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testGlobalBudgetGate() async {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = QuotaPolicy(
            region: .cnMainland,
            profile: .conservative,
            tinPerDay: 1000,
            toutPerDay: 1000,
            reqPerMinute: 5,
            maxConcurrency: 2,
            maxTinPerRequest: 500,
            maxToutPerRequest: 500,
            maxContextTokens: 2000,
            dailyGlobalBudgetUsd: 0.001,
            killSwitchEnabled: false,
            usdPerTinToken: 0.001,
            usdPerToutToken: 0.002
        )

        let manager = QuotaManager(
            store: store,
            policyProvider: { policy },
            dateProvider: FixedDateProvider(now: date)
        )

        do {
            _ = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 10)
            XCTFail("Expected budget error")
        } catch let error as QuotaError {
            XCTAssertEqual(error, .globalBudgetExceeded)
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testProfileSwitching() async throws {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var profile: TrialProfile = .conservative

        let manager = QuotaManager(
            store: store,
            policyProvider: { self.makePolicy(region: .cnMainland, profile: profile) },
            dateProvider: FixedDateProvider(now: date)
        )

        let lease = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 60, estimatedTout: 30, estimatedContextTokens: 100)
        await lease.release()
        profile = .moderate
        let lease2 = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 60, estimatedTout: 30, estimatedContextTokens: 100)
        await lease2.release()
    }

    func testRegionPoliciesDiffer() {
        let cn = makePolicy(region: .cnMainland, profile: .conservative)
        let nonCn = makePolicy(region: .nonCn, profile: .moderate)
        XCTAssertNotEqual(cn.tinPerDay, nonCn.tinPerDay)
        XCTAssertNotEqual(cn.region, nonCn.region)
    }

    func testKillSwitchBlocks() async {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = QuotaPolicy(
            region: .cnMainland,
            profile: .conservative,
            tinPerDay: 100,
            toutPerDay: 50,
            reqPerMinute: 2,
            maxConcurrency: 1,
            maxTinPerRequest: 80,
            maxToutPerRequest: 40,
            maxContextTokens: 2000,
            dailyGlobalBudgetUsd: 1.0,
            killSwitchEnabled: true,
            usdPerTinToken: 0.001,
            usdPerToutToken: 0.002
        )
        let manager = QuotaManager(
            store: store,
            policyProvider: { policy },
            dateProvider: FixedDateProvider(now: date)
        )

        do {
            _ = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 10)
            XCTFail("Expected kill switch error")
        } catch let error as QuotaError {
            XCTAssertEqual(error, .killSwitchActive)
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testConcurrencyLimit() async throws {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = QuotaManager(
            store: store,
            policyProvider: { self.makePolicy(region: .cnMainland, profile: .conservative) },
            dateProvider: FixedDateProvider(now: date)
        )

        let lease = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 10)
        do {
            _ = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 10)
            XCTFail("Expected concurrency error")
        } catch let error as QuotaError {
            XCTAssertEqual(error, .concurrencyLimited)
        } catch {
            XCTFail("Unexpected error")
        }
        await lease.release()
    }

    func testContextTooLarge() async {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = QuotaManager(
            store: store,
            policyProvider: { self.makePolicy(region: .cnMainland, profile: .conservative) },
            dateProvider: FixedDateProvider(now: date)
        )

        do {
            _ = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 1, estimatedTout: 1, estimatedContextTokens: 5000)
            XCTFail("Expected context error")
        } catch let error as QuotaError {
            XCTAssertEqual(error, .contextTooLarge)
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testRequestTooLarge() async {
        let store = InMemoryQuotaStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = QuotaManager(
            store: store,
            policyProvider: { self.makePolicy(region: .cnMainland, profile: .conservative) },
            dateProvider: FixedDateProvider(now: date)
        )

        do {
            _ = try await manager.authorize(deviceIdHash: "dev", estimatedTin: 1000, estimatedTout: 1, estimatedContextTokens: 10)
            XCTFail("Expected request size error")
        } catch let error as QuotaError {
            XCTAssertEqual(error, .requestTooLarge)
        } catch {
            XCTFail("Unexpected error")
        }
    }
}
