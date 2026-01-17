import Foundation
import CoreKit
import TelemetryKit

public struct RecognizedSpanWithConfidence: Codable, Equatable {
    public let span: RecognizedSpan
    public let confidence: Double

    public init(span: RecognizedSpan, confidence: Double) {
        self.span = span
        self.confidence = confidence
    }
}

public protocol OCRProvider {
    func recognize(imageBlobId: String, pageId: String) async throws -> [RecognizedSpanWithConfidence]
}

public final class AppleFirstOCRProvider: OCRProvider {
    private let fixtures: [String: [RecognizedSpanWithConfidence]]

    public init(fixtures: [String: [RecognizedSpanWithConfidence]] = [:]) {
        self.fixtures = fixtures
    }

    public func recognize(imageBlobId: String, pageId: String) async throws -> [RecognizedSpanWithConfidence] {
        fixtures[imageBlobId] ?? []
    }
}

public final class HandwritingIndexer {
    private let store: HandwritingIndexStore
    private let provider: OCRProvider
    private let telemetry: TelemetrySink

    public init(store: HandwritingIndexStore, provider: OCRProvider, telemetry: TelemetrySink = NoopTelemetrySink()) {
        self.store = store
        self.provider = provider
        self.telemetry = telemetry
    }

    public func index(pageId: String, imageBlobId: String) async throws -> [RecognizedSpanWithConfidence] {
        let spans = try await provider.recognize(imageBlobId: imageBlobId, pageId: pageId)
        let normalized = spans.map { span in
            RecognizedSpanWithConfidence(span: normalize(span.span), confidence: span.confidence)
        }
        let entry = HandwritingIndexEntry(pageId: pageId, spans: normalized.map { $0.span })
        var entries = store.loadAll()
        if let index = entries.firstIndex(where: { $0.pageId == pageId }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        store.saveAll(entries)
        telemetry.record(.init(name: "handwriting_indexed", properties: ["pageId": pageId, "count": String(normalized.count)]))
        return normalized
    }

    private func normalize(_ span: RecognizedSpan) -> RecognizedSpan {
        let box = span.bbox
        let normalizedBox = OCRBoundingBox(
            x: clamp(box.x),
            y: clamp(box.y),
            width: clamp(box.width),
            height: clamp(box.height)
        )
        return RecognizedSpan(text: span.text, bbox: normalizedBox, pageId: span.pageId, timestampRange: span.timestampRange)
    }

    private func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
