import Foundation
import TelemetryKit

public protocol SpeechRecognizer {
    func recognize() async throws -> String
}

public protocol TextToSpeech {
    func speak(_ text: String) async throws
}

public final class VoiceQnAController {
    public enum State: Equatable {
        case playing
        case holdToTalk
        case recognizing
        case awaitingAnswer
        case speaking
        case fallbackTyped
    }

    private let recognizer: SpeechRecognizer
    private let tts: TextToSpeech
    private let ask: (String) async throws -> String
    private let telemetry: TelemetrySink

    public private(set) var state: State = .playing

    public init(
        recognizer: SpeechRecognizer,
        tts: TextToSpeech,
        ask: @escaping (String) async throws -> String,
        telemetry: TelemetrySink = NoopTelemetrySink()
    ) {
        self.recognizer = recognizer
        self.tts = tts
        self.ask = ask
        self.telemetry = telemetry
    }

    public func holdToTalk() {
        state = .holdToTalk
        telemetry.record(.init(name: "voice_hold_to_talk", properties: [:]))
    }

    public func startRecognition() async {
        state = .recognizing
        telemetry.record(.init(name: "voice_asr_start", properties: [:]))
        do {
            let transcript = try await recognizer.recognize()
            telemetry.record(.init(name: "voice_asr_success", properties: [:]))
            await handleQuestion(transcript)
        } catch {
            state = .fallbackTyped
            telemetry.record(.init(name: "voice_asr_failed", properties: [:]))
        }
    }

    public func submitTypedQuestion(_ text: String) async {
        await handleQuestion(text)
    }

    private func handleQuestion(_ text: String) async {
        state = .awaitingAnswer
        telemetry.record(.init(name: "voice_question_submitted", properties: [:]))
        do {
            let answer = try await ask(text)
            state = .speaking
            telemetry.record(.init(name: "voice_tts_start", properties: [:]))
            try await tts.speak(answer)
            telemetry.record(.init(name: "voice_tts_done", properties: [:]))
            state = .playing
        } catch {
            state = .fallbackTyped
            telemetry.record(.init(name: "voice_answer_failed", properties: [:]))
        }
    }
}
