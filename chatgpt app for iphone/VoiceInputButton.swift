// VoiceInputButton.swift
// Button for recording and transcribing voice input using Speech framework
import SwiftUI
import Speech

struct VoiceInputButton: View {
    @Binding var isRecording: Bool
    @Binding var transcribedText: String
    @State private var speechRecognizer = SFSpeechRecognizer()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    var body: some View {
        Button(action: { isRecording ? stopRecording() : startRecording() }) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.title)
                .foregroundStyle(isRecording ? .red : .primary)
        }
    }
    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { auth in guard auth == .authorized else { return } }
        recognitionTask?.cancel()
        recognitionTask = nil
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async { transcribedText = result.bestTranscription.formattedString }
            }
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            recognitionRequest.append(buffer)
        }
        audioEngine.prepare(); try? audioEngine.start()
        DispatchQueue.main.async { isRecording = true }
    }
    private func stopRecording() {
        audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        DispatchQueue.main.async { isRecording = false }
    }
}
