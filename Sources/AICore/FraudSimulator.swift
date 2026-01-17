import Foundation
import QuotaKit

public struct FraudSimulationResult: Codable, Equatable {
    public let totalDevices: Int
    public let totalClaims: Int
    public let duplicateClaims: Int
    public let authorizeAttempts: Int
    public let budgetGateTriggered: Int
    public let killSwitchTriggered: Int

    public init(totalDevices: Int, totalClaims: Int, duplicateClaims: Int, authorizeAttempts: Int, budgetGateTriggered: Int, killSwitchTriggered: Int) {
        self.totalDevices = totalDevices
        self.totalClaims = totalClaims
        self.duplicateClaims = duplicateClaims
        self.authorizeAttempts = authorizeAttempts
        self.budgetGateTriggered = budgetGateTriggered
        self.killSwitchTriggered = killSwitchTriggered
    }
}

public final class FraudSimulator {
    private let quotaManager: QuotaManager
    private let claimService: TrialClaimService

    public init(quotaManager: QuotaManager, claimService: TrialClaimService) {
        self.quotaManager = quotaManager
        self.claimService = claimService
    }

    public func simulate(deviceCount: Int, requestsPerDevice: Int, estimatedTin: Int, estimatedTout: Int, estimatedContextTokens: Int) async -> FraudSimulationResult {
        var totalClaims = 0
        var duplicateClaims = 0
        var authorizeAttempts = 0
        var budgetGateTriggered = 0
        var killSwitchTriggered = 0

        for i in 0..<deviceCount {
            let deviceId = "device-\(i)"
            if claimService.claim(deviceId: deviceId) {
                totalClaims += 1
            } else {
                duplicateClaims += 1
            }

            for _ in 0..<requestsPerDevice {
                authorizeAttempts += 1
                do {
                    let lease = try await quotaManager.authorize(
                        deviceIdHash: deviceId,
                        estimatedTin: estimatedTin,
                        estimatedTout: estimatedTout,
                        estimatedContextTokens: estimatedContextTokens
                    )
                    await lease.release()
                } catch let error as QuotaError {
                    switch error {
                    case .globalBudgetExceeded:
                        budgetGateTriggered += 1
                    case .killSwitchActive:
                        killSwitchTriggered += 1
                    default:
                        break
                    }
                } catch {
                    continue
                }
            }
        }

        return FraudSimulationResult(
            totalDevices: deviceCount,
            totalClaims: totalClaims,
            duplicateClaims: duplicateClaims,
            authorizeAttempts: authorizeAttempts,
            budgetGateTriggered: budgetGateTriggered,
            killSwitchTriggered: killSwitchTriggered
        )
    }
}
