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
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
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
        
        // Configure request
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .unspecified
        
        // Use on-device recognition if available (iOS 13+)
        if recognizer?.supportsOnDeviceRecognition ?? false {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // Start recognition
        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    // Update transcript with best transcription
                    self.transcript = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        print("✅ Transcription complete")
                        self.isTranscribing = false
                    }
                }
                
                if let error = error {
                    print("⚠️ Recognition error: \(error.localizedDescription)")
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
}
