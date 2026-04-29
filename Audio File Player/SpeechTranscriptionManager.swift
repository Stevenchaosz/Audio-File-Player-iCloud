import Foundation
import Speech
import AVFoundation
import Observation

// Uses iOS 26 SpeechAnalyzer + SpeechTranscriber APIs:
//   - analyzeSequence(from: AVAudioFile) — no manual request/callback wiring
//   - ResultAttributeOption.audioTimeRange — per-phrase CMTimeRange on the
//     result's AttributedString, eliminating our heuristic sentence-grouping
//   - Results are phrase-level (Apple's model does the sentence breaking)
//   - final actor SpeechAnalyzer — no nonisolated workarounds needed

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

        // Resolve fr-FR to the nearest supported locale
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "fr-FR")
        ) else {
            print("⚠️ fr-FR not supported by SpeechTranscriber")
            return
        }

        // audioTimeRange: attaches a TimeRangeAttribute (CMTimeRange) to each
        // run in the result's AttributedString — enables lyric-sync highlighting
        // without any heuristic timestamp guessing.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        // Download on-device model if not already installed
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

        // Collect phrase results concurrently with analysis.
        // Each result from transcriber.results is already a sentence/phrase —
        // Apple's model handles the segmentation; no manual grouping needed.
        let resultsTask = Task { () -> [TranscriptLine] in
            var collected: [TranscriptLine] = []
            do {
                for try await result in transcriber.results {
                    guard let line = TranscriptLine(from: result) else { continue }
                    collected.append(line)
                }
            } catch {
                print("⚠️ Results stream error: \(error)")
            }
            return collected
        }

        // Feed the file — returns once the file has been fully read
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
}

// MARK: - TranscriptLine initializer from SpeechTranscriber.Result

private extension TranscriptLine {
    // Builds a TranscriptLine from a phrase result.
    // result.range is a CMTimeRange directly on the Result — the phrase's
    // start and end time in the source audio. No attribute iteration needed.
    init?(from result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        self.init(
            id: UUID(),
            text: text,
            startTime: CMTimeGetSeconds(result.range.start),
            endTime: CMTimeGetSeconds(result.range.end)
        )
    }
}
