import Foundation
import Speech
import AVFoundation
import Observation

@MainActor
@Observable
final class SpeechTranscriptionManager {
    // Lyrics-style lines with per-line timestamps for playback sync
    var lines: [TranscriptLine] = []
    // Flat text derived from lines — used for translation input and empty-state checks
    var transcript: String = ""
    var isTranscribing = false
    var transcriptionAvailable = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
        checkAvailability()
    }

    // nonisolated: TCC delivers the authorization callback on a background thread.
    // Marking this method nonisolated prevents Swift from inserting a @MainActor
    // runtime check at the closure's entry point, which would crash on that thread.
    nonisolated func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.authorizationStatus = status
                self?.checkAvailability()
            }
        }
    }

    private func checkAvailability() {
        transcriptionAvailable = recognizer?.isAvailable ?? false
    }

    func transcribe(audioFile: AudioFile) async {
        guard let url = audioFile.resolvedURL else {
            print("⚠️ Could not resolve URL for audio file")
            return
        }
        guard authorizationStatus == .authorized else {
            print("⚠️ Speech recognition not authorized")
            requestAuthorization()
            return
        }
        guard transcriptionAvailable else {
            print("⚠️ Speech recognition not available")
            return
        }

        cancel()
        isTranscribing = true
        lines = []
        transcript = ""

        recognitionRequest = SFSpeechURLRecognitionRequest(url: url)
        guard let recognitionRequest else {
            print("⚠️ Unable to create recognition request")
            isTranscribing = false
            return
        }

        // Partial results accumulate the full text internally; we only consume
        // the final result so we have all segments with accurate timestamps.
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .unspecified
        // Punctuation improves sentence boundary detection for grouping into lines.
        recognitionRequest.addsPunctuation = true

        recognitionTask = Self.startRecognitionTask(
            recognizer: recognizer,
            request: recognitionRequest
        ) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result, result.isFinal {
                    let segments = result.bestTranscription.segments
                    self.lines = Self.groupIntoLines(segments)
                    self.transcript = self.lines.map { $0.text }.joined(separator: " ")
                    print("✅ Transcription complete — \(self.lines.count) lines")
                    self.isTranscribing = false
                }
                if let error {
                    let code = (error as NSError).code
                    if code != 1110 { // 1110 = no speech detected, not a real error
                        print("⚠️ Recognition error: \(error.localizedDescription)")
                    }
                    self.isTranscribing = false
                }
            }
        }
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isTranscribing = false
    }

    func clearTranscript() {
        lines = []
        transcript = ""
    }

    // MARK: - Sentence grouping

    // Groups per-word segments into displayable lines using three signals:
    //   1. Sentence-ending punctuation  (. ! ?)  → always break
    //   2. Clause punctuation           (, ; :)  + pause ≥ 0.4 s → break
    //   3. Long pause between words              ≥ 0.9 s → break
    //   4. Maximum words per line                ≥ 12 → break
    // A minimum of 2 words is required before a mid-clause or max-count break
    // to avoid orphaned single-word lines.
    private static func groupIntoLines(_ segments: [SFTranscriptionSegment]) -> [TranscriptLine] {
        guard !segments.isEmpty else { return [] }

        var result: [TranscriptLine] = []
        var words: [String] = []
        var lineStart: TimeInterval = segments[0].timestamp
        var prevEnd: TimeInterval = 0

        for segment in segments {
            let word = segment.substring
            let wordStart = segment.timestamp
            let wordEnd = wordStart + segment.duration

            let gap = words.isEmpty ? 0.0 : wordStart - prevEnd
            let prevWord = words.last ?? ""
            let prevLastChar = prevWord.last

            let endsWithSentence  = prevLastChar.map { ".!?".contains($0) } ?? false
            let endsWithClause    = prevLastChar.map { ",;:".contains($0) } ?? false
            let longPause         = gap >= 0.9
            let clausePause       = endsWithClause && gap >= 0.4
            let wordCount         = words.count

            let shouldBreak = !words.isEmpty && (
                endsWithSentence ||
                (clausePause    && wordCount >= 2) ||
                (longPause      && wordCount >= 2) ||
                (wordCount >= 12)
            )

            if shouldBreak {
                result.append(TranscriptLine(
                    id: UUID(),
                    text: words.joined(separator: " "),
                    startTime: lineStart,
                    endTime: prevEnd
                ))
                words = [word]
                lineStart = wordStart
            } else {
                words.append(word)
            }

            prevEnd = wordEnd
        }

        if !words.isEmpty {
            result.append(TranscriptLine(
                id: UUID(),
                text: words.joined(separator: " "),
                startTime: lineStart,
                endTime: prevEnd
            ))
        }

        return result
    }

    // Static nonisolated so the callback closure isn't created in a @MainActor context,
    // preventing Swift from inserting a main-actor isolation check at the closure entry.
    private static nonisolated func startRecognitionTask(
        recognizer: SFSpeechRecognizer?,
        request: SFSpeechRecognitionRequest,
        handler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask? {
        recognizer?.recognitionTask(with: request, resultHandler: handler)
    }
}
