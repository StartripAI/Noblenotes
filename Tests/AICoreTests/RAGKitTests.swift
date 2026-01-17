import XCTest
@testable import AICore

final class RAGKitTests: XCTestCase {
    func testMissingMetadataThrows() {
        let chunk = Chunk(sourceId: "", page: nil, timeRange: nil, text: "missing")
        let retriever = DeterministicHybridRetriever(bm25: [chunk], vector: [])
        let pipeline = CitationAnsweringPipeline(retriever: retriever, reranker: NoopReranker())

        XCTAssertThrowsError(try pipeline.answerWithCitations(question: "q")) { error in
            XCTAssertEqual(error as? CitationError, .missingMetadata)
        }
    }

    func testCitationsStableOrdering() throws {
        let first = Chunk(sourceId: "s1", page: 1, timeRange: nil, text: "alpha")
        let second = Chunk(sourceId: "s2", page: 2, timeRange: nil, text: "beta")
        let retriever = DeterministicHybridRetriever(bm25: [first, second], vector: [second])
        let pipeline = CitationAnsweringPipeline(retriever: retriever, reranker: NoopReranker())

        let result = try pipeline.answerWithCitations(question: "q")
        XCTAssertEqual(result.citations.map { $0.sourceId }, ["s1", "s2"])
    }
}
