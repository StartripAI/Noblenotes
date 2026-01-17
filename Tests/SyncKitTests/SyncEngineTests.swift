import XCTest
@testable import SyncKit
import CoreKit

final class SyncEngineTests: XCTestCase {
    func testDiffOutput() {
        let engine = LineDiffEngine()
        let diff = engine.diff(base: "a\nb", updated: "a\nc")
        XCTAssertEqual(diff.operations.count, 1)
        XCTAssertEqual(diff.operations.first?.kind, .replace)
    }

    func testConflictCopyGenerated() throws {
        let engine = SyncEngine()
        let base = SyncRecord(id: "1", revision: Revision(version: 1, author: "server"), payload: "hello")
        let server = SyncRecord(id: "1", revision: Revision(version: 1, author: "server"), payload: "server")
        let local = SyncRecord(id: "1", revision: Revision(version: 1, author: "local"), payload: "local")

        let outcome = try engine.reconcile(local: local, server: server, base: base)
        XCTAssertEqual(outcome.conflictCopies.count, 1)
        XCTAssertTrue(outcome.conflictCopies[0].id.contains("conflict"))
        XCTAssertEqual(outcome.historyEntries.count, 1)
    }

    func testOccReject() {
        let engine = SyncEngine()
        let base = SyncRecord(id: "1", revision: Revision(version: 1, author: "server"), payload: "hello")
        let server = SyncRecord(id: "1", revision: Revision(version: 2, author: "server"), payload: "server")
        let local = SyncRecord(id: "1", revision: Revision(version: 1, author: "local"), payload: "local")

        XCTAssertThrowsError(try engine.reconcile(local: local, server: server, base: base)) { error in
            XCTAssertEqual(error as? SyncError, .occConflict)
        }
    }

    func testMergeSuggestionKeepsServerWhenLocalUnchanged() throws {
        let resolver = RuleBasedConflictResolver()
        let suggestions = resolver.suggest(local: "base", server: "server", base: "base")
        XCTAssertEqual(suggestions.first?.strategy, .keepServer)
    }

    func testRollbackFromHistory() {
        let engine = SyncEngine()
        let record = SyncRecord(id: "1", revision: Revision(version: 1, author: "local"), payload: "v1")
        let (updated, history) = engine.applyLocalChange(record: record, newPayload: "v2", author: "local")
        let rollback = engine.rollback(record: updated, history: history, author: "local")
        XCTAssertEqual(rollback.payload, "v1")
        XCTAssertEqual(rollback.revision.version, 3)
    }
}
