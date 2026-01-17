import XCTest
@testable import AICore
import TelemetryKit

final class VoiceQnAControllerTests: XCTestCase {
    final class StubRecognizer: SpeechRecognizer {
        let result: Result<String, Error>
        init(result: Result<String, Error>) { self.result = result }
        func recognize() async throws -> String { try result.get() }
    }

    final class StubTTS: TextToSpeech {
        var spoken: [String] = []
        func speak(_ text: String) async throws { spoken.append(text) }
    }

    final class CapturingTelemetry: TelemetrySink {
        var events: [TelemetryEvent] = []
        func record(_ event: TelemetryEvent) { events.append(event) }
    }

    struct DummyError: Error {}

    func testStateTransitionsHappyPath() async {
        let telemetry = CapturingTelemetry()
        let recognizer = StubRecognizer(result: .success("hello"))
        let tts = StubTTS()
        let controller = VoiceQnAController(
            recognizer: recognizer,
            tts: tts,
            ask: { _ in "answer" },
            telemetry: telemetry
        )

        controller.holdToTalk()
        await controller.startRecognition()

        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(tts.spoken.first, "answer")
        XCTAssertTrue(telemetry.events.map { $0.name }.contains("voice_tts_done"))
    }

    func testFallbackOnAsrFailure() async {
        let telemetry = CapturingTelemetry()
        let recognizer = StubRecognizer(result: .failure(DummyError()))
        let tts = StubTTS()
        let controller = VoiceQnAController(
            recognizer: recognizer,
            tts: tts,
            ask: { _ in "answer" },
            telemetry: telemetry
        )

        controller.holdToTalk()
        await controller.startRecognition()

        XCTAssertEqual(controller.state, .fallbackTyped)
        XCTAssertTrue(telemetry.events.map { $0.name }.contains("voice_asr_failed"))
    }

    func testTypedQuestionAfterFallback() async {
        let telemetry = CapturingTelemetry()
        let recognizer = StubRecognizer(result: .failure(DummyError()))
        let tts = StubTTS()
        let controller = VoiceQnAController(
            recognizer: recognizer,
            tts: tts,
            ask: { _ in "typed-answer" },
            telemetry: telemetry
        )

        controller.holdToTalk()
        await controller.startRecognition()
        await controller.submitTypedQuestion("typed")

        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(tts.spoken.first, "typed-answer")
        XCTAssertTrue(telemetry.events.map { $0.name }.contains("voice_question_submitted"))
    }
}
