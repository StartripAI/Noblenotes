import Foundation
import CoreKit

public struct DailyMetricsReport: Codable, Equatable {
    public let onDeviceHitRate: Double
    public let cnVsNonCnSplit: CNNonCNSplit
    public let quotaDeniedCount: Int
    public let budgetGateTriggerCount: Int

    public init(onDeviceHitRate: Double, cnVsNonCnSplit: CNNonCNSplit, quotaDeniedCount: Int, budgetGateTriggerCount: Int) {
        self.onDeviceHitRate = onDeviceHitRate
        self.cnVsNonCnSplit = cnVsNonCnSplit
        self.quotaDeniedCount = quotaDeniedCount
        self.budgetGateTriggerCount = budgetGateTriggerCount
    }
}

public struct CNNonCNSplit: Codable, Equatable {
    public let cn: Double
    public let nonCn: Double

    public init(cn: Double, nonCn: Double) {
        self.cn = cn
        self.nonCn = nonCn
    }
}

public final class TelemetryAggregator {
    private let inputDirectory: URL
    private let outputFile: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        inputDirectory: URL = URL(fileURLWithPath: "TelemetryLogs", isDirectory: true),
        outputFile: URL = URL(fileURLWithPath: "Reports/daily_metrics.json"),
        fileManager: FileManager = .default
    ) {
        self.inputDirectory = inputDirectory
        self.outputFile = outputFile
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func generateReport() throws -> DailyMetricsReport {
        let events = try loadEvents()
        let report = buildReport(events: events)
        try writeReport(report)
        return report
    }

    private func loadEvents() throws -> [TelemetryEvent] {
        guard fileManager.fileExists(atPath: inputDirectory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: inputDirectory, includingPropertiesForKeys: nil)
        let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }
        var events: [TelemetryEvent] = []
        for file in jsonlFiles {
            let data = try Data(contentsOf: file)
            let lines = data.split(separator: 10)
            for line in lines {
                if let event = try? decoder.decode(TelemetryEvent.self, from: Data(line)) {
                    events.append(event)
                }
            }
        }
        return events
    }

    private func buildReport(events: [TelemetryEvent]) -> DailyMetricsReport {
        var onDevice = 0
        var cloud = 0
        var cn = 0
        var nonCn = 0
        var quotaDenied = 0
        var budgetGate = 0

        for event in events {
            switch event.name {
            case "provider_on_device":
                onDevice += 1
            case "provider_cloud":
                cloud += 1
            case "quota_denied":
                quotaDenied += 1
                if event.properties["reason"] == "globalBudget" {
                    budgetGate += 1
                }
            default:
                break
            }

            if let region = event.properties["region"] {
                if region == Region.cnMainland.rawValue {
                    cn += 1
                } else if region == Region.nonCn.rawValue {
                    nonCn += 1
                }
            }
        }

        let providerTotal = onDevice + cloud
        let onDeviceRate = providerTotal == 0 ? 0.0 : Double(onDevice) / Double(providerTotal)
        let regionTotal = cn + nonCn
        let cnRate = regionTotal == 0 ? 0.0 : Double(cn) / Double(regionTotal)
        let nonCnRate = regionTotal == 0 ? 0.0 : Double(nonCn) / Double(regionTotal)

        return DailyMetricsReport(
            onDeviceHitRate: onDeviceRate,
            cnVsNonCnSplit: CNNonCNSplit(cn: cnRate, nonCn: nonCnRate),
            quotaDeniedCount: quotaDenied,
            budgetGateTriggerCount: budgetGate
        )
    }

    private func writeReport(_ report: DailyMetricsReport) throws {
        let outputDirectory = outputFile.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(report)
        try data.write(to: outputFile, options: .atomic)
    }
}
