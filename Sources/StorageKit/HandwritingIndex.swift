import Foundation
import CoreKit

public struct OCRBoundingBox: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct TimestampRange: Codable, Equatable {
    public let start: ISO8601Timestamp
    public let end: ISO8601Timestamp

    public init(start: ISO8601Timestamp, end: ISO8601Timestamp) {
        self.start = start
        self.end = end
    }
}

public struct RecognizedSpan: Codable, Equatable {
    public let text: String
    public let bbox: OCRBoundingBox
    public let pageId: String
    public let timestampRange: TimestampRange?

    public init(text: String, bbox: OCRBoundingBox, pageId: String, timestampRange: TimestampRange? = nil) {
        self.text = text
        self.bbox = bbox
        self.pageId = pageId
        self.timestampRange = timestampRange
    }
}

public struct HandwritingIndexEntry: Codable, Equatable {
    public let pageId: String
    public let spans: [RecognizedSpan]

    public init(pageId: String, spans: [RecognizedSpan]) {
        self.pageId = pageId
        self.spans = spans
    }
}

public struct HandwritingIndexHit: Codable, Equatable {
    public let text: String
    public let pageId: String
    public let bbox: OCRBoundingBox

    public init(text: String, pageId: String, bbox: OCRBoundingBox) {
        self.text = text
        self.pageId = pageId
        self.bbox = bbox
    }
}

public protocol HandwritingIndexStore {
    func loadAll() -> [HandwritingIndexEntry]
    func saveAll(_ entries: [HandwritingIndexEntry])
}

public final class KeyValueHandwritingIndexStore: HandwritingIndexStore {
    private let store: KeyValueStore
    private let key = "handwriting_index_entries"

    public init(store: KeyValueStore) {
        self.store = store
    }

    public func loadAll() -> [HandwritingIndexEntry] {
        store.load(key: key) ?? []
    }

    public func saveAll(_ entries: [HandwritingIndexEntry]) {
        store.save(key: key, value: entries)
    }
}

public final class HandwritingIndex {
    private let store: HandwritingIndexStore

    public init(store: HandwritingIndexStore) {
        self.store = store
    }

    public func upsert(entry: HandwritingIndexEntry) {
        var entries = store.loadAll()
        if let index = entries.firstIndex(where: { $0.pageId == entry.pageId }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        store.saveAll(entries)
    }

    public func search(query: String) -> [HandwritingIndexHit] {
        let lowercased = query.lowercased()
        return store.loadAll().flatMap { entry in
            entry.spans.compactMap { span in
                guard span.text.lowercased().contains(lowercased) else { return nil }
                return HandwritingIndexHit(text: span.text, pageId: entry.pageId, bbox: span.bbox)
            }
        }
    }
}
