import Foundation
import Speech
import AVFoundation
import Observation

@MainActor
@Observable
final class SpeechTranscriptionManager {
    var lines: [TranscriptLine] = []
    var transcript: String = ""
    var isTranscribing = false

    var isAvailable: Bool { SpeechTranscriber.isAvailable }

    private var currentTask: Task<Void, Never>?

    func transcribe(audioFile: AudioFile) async {
        guard let url = audioFile.resolvedURL else {
            print("⚠️ Could not resolve URL for audio file")
            return
        }
        guard SpeechTranscriber.isAvailable else {
            print("⚠️ SpeechTranscriber not available on this device")
            return
        }

        cancel()
        isTranscribing = true
        lines = []
        transcript = ""

        currentTask = Task { [weak self] in
            await self?.runTranscription(url: url)
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isTranscribing = false
    }

    func clearTranscript() {
        lines = []
        transcript = ""
    }

    // MARK: - Core transcription

    private func runTranscription(url: URL) async {
        defer { isTranscribing = false }

        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "fr-FR")
        ) else {
            print("⚠️ fr-FR not supported by SpeechTranscriber")
            return
        }

        // audioTimeRange attaches a per-word CMTimeRange to each run of the
        // result's AttributedString via AttributeScopes.SpeechAttributes.
        // We use this to get exact timestamps when splitting chunks into sentences.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        do {
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                print("📥 Installing speech recognition model…")
                try await request.downloadAndInstall()
            }
        } catch {
            print("⚠️ Asset installation error: \(error) — attempting anyway")
        }

        guard let avFile = try? AVAudioFile(forReading: url) else {
            print("⚠️ Could not open audio file")
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Collect results concurrently with analysis. Each result may be a
        // multi-sentence paragraph chunk; splitIntoSentences() breaks it into
        // individual sentence lines using the per-word TimeRangeAttribute.
        let resultsTask = Task { () -> [TranscriptLine] in
            var collected: [TranscriptLine] = []
            do {
                for try await result in transcriber.results {
                    collected.append(contentsOf: Self.splitIntoSentences(result))
                }
            } catch {
                print("⚠️ Results stream error: \(error)")
            }
            return collected
        }

        do {
            let lastTime = try await analyzer.analyzeSequence(from: avFile)
            if let lastTime {
                try await analyzer.finalizeAndFinish(through: lastTime)
            } else {
                try await analyzer.cancelAndFinishNow()
            }
        } catch {
            print("⚠️ Analysis error: \(error)")
        }

        guard !Task.isCancelled else { return }

        let collected = await resultsTask.value
        print("✅ Transcription complete — \(collected.count) lines")
        lines = collected
        transcript = collected.map { $0.text }.joined(separator: " ")
    }

    // MARK: - Sentence splitting

    // Splits a single result (which may be a multi-sentence paragraph) into
    // individual TranscriptLines using per-word timing.
    //
    // How it works:
    //   1. Walk result.text.runs. Each run with an AudioTimeRange attribute is
    //      a word token; its CMTimeRange gives exact start/end in the audio.
    //   2. Accumulate words into a sentence until a token ends with . ! or ?
    //   3. Build a TranscriptLine whose startTime = first word's start,
    //      endTime = last word's end.
    //
    // Fallback: if no per-word timing is present (attributeOptions weren't set,
    // or the model returned no attributes), the whole result becomes one line
    // using result.range directly.
    private static func splitIntoSentences(_ result: SpeechTranscriber.Result) -> [TranscriptLine] {
        // Collect (wordText, CMTimeRange) for every timed run
        var wordTimings: [(text: String, range: CMTimeRange)] = []
        for run in result.text.runs {
            let word = String(result.text[run.range].characters)
                .trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            if let tr = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] {
                wordTimings.append((word, tr))
            }
        }

        // Fallback: no per-word timing → whole chunk is one line
        guard !wordTimings.isEmpty else {
            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptLine(
                id: UUID(), text: text,
                startTime: CMTimeGetSeconds(result.range.start),
                endTime:   CMTimeGetSeconds(result.range.end)
            )]
        }

        // Group words into sentences, breaking at . ! ?
        var lines: [TranscriptLine] = []
        var bucket: [(text: String, range: CMTimeRange)] = []

        for wt in wordTimings {
            bucket.append(wt)
            let last = wt.text
            if last.hasSuffix(".") || last.hasSuffix("!") || last.hasSuffix("?") {
                if let line = makeLine(from: bucket) { lines.append(line) }
                bucket = []
            }
        }
        // Flush any trailing words that didn't end with punctuation
        if !bucket.isEmpty, let line = makeLine(from: bucket) {
            lines.append(line)
        }

        return lines
    }

    private static func makeLine(from words: [(text: String, range: CMTimeRange)]) -> TranscriptLine? {
        guard let first = words.first, let last = words.last else { return nil }
        let text = words.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return TranscriptLine(
            id: UUID(), text: text,
            startTime: CMTimeGetSeconds(first.range.start),
            endTime:   CMTimeGetSeconds(last.range.end)
        )
    }
}
