import XCTest
@testable import StorageKit
import CoreKit

final class HandwritingIndexTests: XCTestCase {
    func testSearchReturnsHits() {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueHandwritingIndexStore(store: kv)
        let index = HandwritingIndex(store: store)

        let span = RecognizedSpan(
            text: "Physics note",
            bbox: OCRBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            pageId: "page-1",
            timestampRange: TimestampRange(start: ISO8601Timestamp(Date(timeIntervalSince1970: 1)), end: ISO8601Timestamp(Date(timeIntervalSince1970: 2)))
        )
        index.upsert(entry: HandwritingIndexEntry(pageId: "page-1", spans: [span]))

        let hits = index.search(query: "physics")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.pageId, "page-1")
        XCTAssertEqual(hits.first?.bbox.width, 0.3)
    }

    func testUpsertReplacesPage() {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueHandwritingIndexStore(store: kv)
        let index = HandwritingIndex(store: store)

        let span1 = RecognizedSpan(text: "Math", bbox: OCRBoundingBox(x: 0, y: 0, width: 1, height: 1), pageId: "page-1")
        let span2 = RecognizedSpan(text: "Chem", bbox: OCRBoundingBox(x: 0, y: 0, width: 1, height: 1), pageId: "page-1")

        index.upsert(entry: HandwritingIndexEntry(pageId: "page-1", spans: [span1]))
        index.upsert(entry: HandwritingIndexEntry(pageId: "page-1", spans: [span2]))

        let hits = index.search(query: "chem")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.text, "Chem")
    }
}
