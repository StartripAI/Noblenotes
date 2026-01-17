import XCTest
@testable import TelemetryKit
import CoreKit

final class TelemetryAggregatorTests: XCTestCase {
    func testAggregatorProducesDeterministicReport() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let logsDir = tempDir.appendingPathComponent("TelemetryLogs", isDirectory: true)
        let reportsDir = tempDir.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

        let sink = FileTelemetrySink(directoryURL: logsDir, fileName: "events.jsonl")
        sink.record(.init(name: "provider_on_device", properties: ["region": Region.nonCn.rawValue]))
        sink.record(.init(name: "provider_cloud", properties: ["region": Region.cnMainland.rawValue]))
        sink.record(.init(name: "provider_cloud", properties: ["region": Region.cnMainland.rawValue]))
        sink.record(.init(name: "quota_denied", properties: ["region": Region.cnMainland.rawValue, "reason": "globalBudget"]))
        sink.record(.init(name: "quota_denied", properties: ["region": Region.nonCn.rawValue, "reason": "rateLimit"]))

        let outputFile = reportsDir.appendingPathComponent("daily_metrics.json")
        let aggregator = TelemetryAggregator(inputDirectory: logsDir, outputFile: outputFile)
        let report = try aggregator.generateReport()

        XCTAssertEqual(report.quotaDeniedCount, 2)
        XCTAssertEqual(report.budgetGateTriggerCount, 1)
        XCTAssertEqual(report.onDeviceHitRate, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(report.cnVsNonCnSplit.cn, 0.6, accuracy: 0.0001)
        XCTAssertEqual(report.cnVsNonCnSplit.nonCn, 0.4, accuracy: 0.0001)

        let data = try Data(contentsOf: outputFile)
        XCTAssertFalse(data.isEmpty)
    }
}
