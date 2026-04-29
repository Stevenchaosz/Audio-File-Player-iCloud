import Foundation
import Speech
import AVFoundation
import Observation

@MainActor
@Observable
final class SpeechTranscriptionManager {
    var transcript: String = ""
    var isTranscribing = false
    var transcriptionAvailable = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    init() {
        // Initialize with French locale
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
        checkAvailability()
    }
    
    // nonisolated is required: SFSpeechRecognizer delivers this callback on a
    // background thread via TCC. If the method is @MainActor-isolated (which it
    // would be implicitly as a member of this class), Swift 5.9+ inserts a
    // runtime actor check at the entry of the callback closure. That check fires
    // the moment TCC calls the closure on a background thread — crash.
    // Making this method nonisolated prevents Swift from inferring @MainActor
    // on the closure. The Task { @MainActor in } then hops correctly.
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
        
        // Cancel any ongoing transcription
        cancel()
        
        isTranscribing = true
        transcript = ""
        
        // Create recognition request
        recognitionRequest = SFSpeechURLRecognitionRequest(url: url)
        
        guard let recognitionRequest = recognitionRequest else {
            print("⚠️ Unable to create recognition request")
            isTranscribing = false
            return
        }
        
        // Configure request.
        // shouldReportPartialResults = true so the framework accumulates text
        // across the entire file. We only push text to the UI when isFinal,
        // giving batch-style behaviour without the chunk-overwrite problem.
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .unspecified

        // Route through a nonisolated static helper so the callback closure is
        // not created inside a @MainActor context — same reason as requestAuthorization.
        recognitionTask = Self.startRecognitionTask(
            recognizer: recognizer,
            request: recognitionRequest
        ) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result, result.isFinal {
                    // Only show text when the recognizer has finalised — avoids
                    // mid-sentence replacements and chunk-overwrite truncation.
                    self.transcript = result.bestTranscription.formattedString
                    print("✅ Transcription complete")
                    self.isTranscribing = false
                }
                if let error {
                    let code = (error as NSError).code
                    // Code 1110 = no speech detected (not a real error)
                    if code != 1110 {
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
        transcript = ""
    }

    // Static nonisolated: closures created here are not in a @MainActor context,
    // so Swift won't insert an actor isolation check at their entry points.
    private static nonisolated func startRecognitionTask(
        recognizer: SFSpeechRecognizer?,
        request: SFSpeechRecognitionRequest,
        handler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask? {
        recognizer?.recognitionTask(with: request, resultHandler: handler)
    }
}
