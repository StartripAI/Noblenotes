import XCTest
@testable import StorageKit
import CoreKit

final class OCRPipelineTests: XCTestCase {
    func testIndexingStoresSpansAndSearchFinds() async throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueHandwritingIndexStore(store: kv)
        let span = RecognizedSpan(text: "Hello", bbox: OCRBoundingBox(x: 0.2, y: 0.3, width: 0.4, height: 0.1), pageId: "page")
        let provider = AppleFirstOCRProvider(fixtures: ["img": [RecognizedSpanWithConfidence(span: span, confidence: 0.9)]])
        let indexer = HandwritingIndexer(store: store, provider: provider)

        _ = try await indexer.index(pageId: "page", imageBlobId: "img")
        let index = HandwritingIndex(store: store)
        let hits = index.search(query: "hello")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.pageId, "page")
    }

    func testNormalizationClampsBoundingBox() async throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueHandwritingIndexStore(store: kv)
        let span = RecognizedSpan(text: "Clamp", bbox: OCRBoundingBox(x: -0.2, y: 1.2, width: 1.5, height: -0.5), pageId: "page")
        let provider = AppleFirstOCRProvider(fixtures: ["img": [RecognizedSpanWithConfidence(span: span, confidence: 0.8)]])
        let indexer = HandwritingIndexer(store: store, provider: provider)

        let normalized = try await indexer.index(pageId: "page", imageBlobId: "img")
        let box = normalized.first?.span.bbox
        XCTAssertEqual(box?.x, 0.0)
        XCTAssertEqual(box?.y, 1.0)
        XCTAssertEqual(box?.width, 1.0)
        XCTAssertEqual(box?.height, 0.0)
    }

    func testLowConfidenceSpanStored() async throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueHandwritingIndexStore(store: kv)
        let span = RecognizedSpan(text: "Low", bbox: OCRBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2), pageId: "page")
        let provider = AppleFirstOCRProvider(fixtures: ["img": [RecognizedSpanWithConfidence(span: span, confidence: 0.05)]])
        let indexer = HandwritingIndexer(store: store, provider: provider)

        let normalized = try await indexer.index(pageId: "page", imageBlobId: "img")
        XCTAssertEqual(normalized.first?.confidence, 0.05)
        let entry = store.loadAll().first
        XCTAssertEqual(entry?.spans.first?.text, "Low")
    }
}
