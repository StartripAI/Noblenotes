import SwiftUI
import AICore
import CoreKit
import QuotaKit
import StorageKit
import TelemetryKit

final class DebugHarness: ObservableObject {
    @Published var providerResult: String = "—"
    @Published var quotaResult: String = "—"
    @Published var searchHits: [HandwritingIndexHit] = []

    private let quotaManager: QuotaManager
    private let router: ProviderRouter
    private let handwritingIndex: HandwritingIndex

    init() {
        let store = InMemoryQuotaStore()
        let catalog = QuotaPolicyCatalog(
            cnConservative: QuotaPolicy(
                region: .cnMainland,
                profile: .conservative,
                tinPerDay: 100,
                toutPerDay: 50,
                reqPerMinute: 3,
                maxConcurrency: 2,
                maxTinPerRequest: 80,
                maxToutPerRequest: 40,
                maxContextTokens: 2048,
                dailyGlobalBudgetUsd: 1.0,
                killSwitchEnabled: false,
                usdPerTinToken: 0.001,
                usdPerToutToken: 0.002
            ),
            cnModerate: QuotaPolicy(
                region: .cnMainland,
                profile: .moderate,
                tinPerDay: 200,
                toutPerDay: 100,
                reqPerMinute: 5,
                maxConcurrency: 2,
                maxTinPerRequest: 120,
                maxToutPerRequest: 80,
                maxContextTokens: 4096,
                dailyGlobalBudgetUsd: 2.0,
                killSwitchEnabled: false,
                usdPerTinToken: 0.001,
                usdPerToutToken: 0.002
            ),
            nonCnConservative: QuotaPolicy(
                region: .nonCn,
                profile: .conservative,
                tinPerDay: 150,
                toutPerDay: 75,
                reqPerMinute: 4,
                maxConcurrency: 2,
                maxTinPerRequest: 80,
                maxToutPerRequest: 40,
                maxContextTokens: 4096,
                dailyGlobalBudgetUsd: 2.5,
                killSwitchEnabled: false,
                usdPerTinToken: 0.001,
                usdPerToutToken: 0.002
            ),
            nonCnModerate: QuotaPolicy(
                region: .nonCn,
                profile: .moderate,
                tinPerDay: 250,
                toutPerDay: 125,
                reqPerMinute: 6,
                maxConcurrency: 3,
                maxTinPerRequest: 150,
                maxToutPerRequest: 100,
                maxContextTokens: 4096,
                dailyGlobalBudgetUsd: 3.0,
                killSwitchEnabled: false,
                usdPerTinToken: 0.001,
                usdPerToutToken: 0.002
            )
        )
        let policyProvider = ConfigBackedQuotaPolicyProvider(catalog: catalog)
        let quotaManager = QuotaManager(store: store, policyProvider: policyProvider)
        let localProvider = LocalProvider(capabilities: AIProviderCapabilities(supportsOffline: true, supportsChinese: true, maxContextTokens: 2048))
        let cloudProvider = CloudProvider(capabilities: AIProviderCapabilities(supportsOffline: false, supportsChinese: true, maxContextTokens: 16000))
        let router = ProviderRouter(
            onDeviceProvider: localProvider,
            cloudProvider: cloudProvider,
            capabilityGate: CapabilityGate(),
            quotaManager: quotaManager
        )
        let keyValueStore = InMemoryKeyValueStore()
        let handwritingStore = KeyValueHandwritingIndexStore(store: keyValueStore)
        let handwritingIndex = HandwritingIndex(store: handwritingStore)
        let fixture = HandwritingIndexEntry(pageId: "page-1", spans: [
            RecognizedSpan(text: "Meeting notes", bbox: OCRBoundingBox(x: 0.1, y: 0.1, width: 0.4, height: 0.2), pageId: "page-1"),
            RecognizedSpan(text: "Budget review", bbox: OCRBoundingBox(x: 0.2, y: 0.4, width: 0.4, height: 0.2), pageId: "page-1")
        ])
        handwritingIndex.upsert(entry: fixture)

        self.quotaManager = quotaManager
        self.router = router
        self.handwritingIndex = handwritingIndex
        self.searchHits = handwritingIndex.search(query: "notes")
    }

    @MainActor
    func routeProvider() async {
        let request = AIRequest(
            task: AITask(kind: .summary, requiresCitations: false, minContextTokens: 50),
            localeIdentifier: "en_US",
            input: "Summarize this page",
            estimatedTin: 20,
            estimatedTout: 10,
            estimatedContextTokens: 200
        )
        do {
            let routed = try await router.route(request: request, region: .nonCn, deviceIdHash: "debug-device")
            providerResult = routed.provider.kind.rawValue
            await routed.lease.release()
        } catch {
            providerResult = "error: \(error)"
        }
    }

    @MainActor
    func checkQuota() async {
        do {
            let lease = try await quotaManager.authorize(deviceIdHash: "debug-device", estimatedTin: 5, estimatedTout: 5, estimatedContextTokens: 100)
            quotaResult = "allowed"
            await lease.release()
        } catch {
            quotaResult = "denied: \(error)"
        }
    }

    @MainActor
    func runSearch(query: String) {
        searchHits = handwritingIndex.search(query: query)
    }
}

struct DebugView: View {
    @StateObject private var harness = DebugHarness()
    @State private var query = "notes"

    var body: some View {
        List {
            Section("ProviderRouter") {
                Text("Result: \(harness.providerResult)")
                Button("Route Provider") {
                    Task {
                        await harness.routeProvider()
                    }
                }
            }

            Section("QuotaManager") {
                Text("Result: \(harness.quotaResult)")
                Button("Authorize") {
                    Task {
                        await harness.checkQuota()
                    }
                }
            }

            Section("Handwriting Search") {
                TextField("Search", text: $query)
                Button("Run Search") {
                    harness.runSearch(query: query)
                }
                ForEach(harness.searchHits, id: \.text) { hit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.text)
                            .font(.headline)
                        Text("Page \(hit.pageId) · bbox \(hit.bbox.x, specifier: "%.2f"), \(hit.bbox.y, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Debug")
    }
}

#Preview {
    DebugView()
}
