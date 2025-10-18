// Alternative speech recognizer implementation to avoid name conflict with existing SpeechRecognizer
import Foundation
import Speech
import AVFoundation

final class SpeechRecognizerV2 {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    func startRecording() throws {
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { fatalError("Unable to create a recognition request") }
        
        request.shouldReportPartialResults = true
        
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = false // set true if you prefer strictly on-device
        }
        request.taskHint = .dictation
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputNode.outputFormat(forBus: 0)) { (buffer, when) in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                print("Transcription: \(result.bestTranscription.formattedString)")
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
    }
}

