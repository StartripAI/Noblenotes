import Foundation

public struct Chunk: Codable, Equatable {
    public let sourceId: String
    public let page: Int?
    public let timeRange: String?
    public let text: String
    public let snippetHash: String

    public init(sourceId: String, page: Int? = nil, timeRange: String? = nil, text: String) {
        self.sourceId = sourceId
        self.page = page
        self.timeRange = timeRange
        self.text = text
        self.snippetHash = Chunk.hash(text)
    }

    public static func hash(_ text: String) -> String {
        return String(text.hashValue)
    }
}

public protocol Chunker {
    func chunk(text: String, sourceId: String) -> [Chunk]
}

public struct LineChunker: Chunker {
    public init() {}

    public func chunk(text: String, sourceId: String) -> [Chunk] {
        text.split(separator: "\n").enumerated().map { index, line in
            Chunk(sourceId: sourceId, page: index + 1, text: String(line))
        }
    }
}

public protocol HybridRetriever {
    func retrieve(query: String) -> [Chunk]
}

public struct DeterministicHybridRetriever: HybridRetriever {
    private let bm25: [Chunk]
    private let vector: [Chunk]

    public init(bm25: [Chunk], vector: [Chunk]) {
        self.bm25 = bm25
        self.vector = vector
    }

    public func retrieve(query: String) -> [Chunk] {
        var seen = Set<String>()
        var merged: [Chunk] = []
        for chunk in bm25 + vector {
            if !seen.contains(chunk.snippetHash) {
                merged.append(chunk)
                seen.insert(chunk.snippetHash)
            }
        }
        return merged
    }
}

public protocol Reranker {
    func rerank(query: String, chunks: [Chunk]) -> [Chunk]
}

public struct NoopReranker: Reranker {
    public init() {}

    public func rerank(query: String, chunks: [Chunk]) -> [Chunk] {
        chunks
    }
}

public struct Citation: Codable, Equatable {
    public let sourceId: String
    public let snippetHash: String
    public let page: Int?
    public let timeRange: String?

    public init(sourceId: String, snippetHash: String, page: Int?, timeRange: String?) {
        self.sourceId = sourceId
        self.snippetHash = snippetHash
        self.page = page
        self.timeRange = timeRange
    }
}

public enum CitationError: Error, Equatable {
    case missingMetadata
}

public struct CitationBuilder {
    public init() {}

    public func build(from chunks: [Chunk]) throws -> [Citation] {
        var citations: [Citation] = []
        for chunk in chunks {
            guard !chunk.sourceId.isEmpty, !chunk.snippetHash.isEmpty else {
                throw CitationError.missingMetadata
            }
            citations.append(Citation(sourceId: chunk.sourceId, snippetHash: chunk.snippetHash, page: chunk.page, timeRange: chunk.timeRange))
        }
        return citations
    }
}

public struct AnswerWithCitations: Codable, Equatable {
    public let answerText: String
    public let citations: [Citation]

    public init(answerText: String, citations: [Citation]) {
        self.answerText = answerText
        self.citations = citations
    }
}

public struct CitationAnsweringPipeline {
    private let retriever: HybridRetriever
    private let reranker: Reranker
    private let citationBuilder: CitationBuilder

    public init(retriever: HybridRetriever, reranker: Reranker, citationBuilder: CitationBuilder = CitationBuilder()) {
        self.retriever = retriever
        self.reranker = reranker
        self.citationBuilder = citationBuilder
    }

    public func answerWithCitations(question: String) throws -> AnswerWithCitations {
        let retrieved = retriever.retrieve(query: question)
        let ranked = reranker.rerank(query: question, chunks: retrieved)
        let citations = try citationBuilder.build(from: ranked)
        let answer = "Answer to: \(question)"
        return AnswerWithCitations(answerText: answer, citations: citations)
    }
}
