import Foundation
import Speech
import AVFoundation

final class SpeechRecognizer: NSObject {
    enum State { case idle, requestingAuth, ready, recognizing }

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var state: State = .idle

    // Callbacks
    var onAuthorization: ((SFSpeechRecognizerAuthorizationStatus) -> Void)?
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        if let locale = Locale.preferredLanguages.first {
            self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        } else {
            self.recognizer = SFSpeechRecognizer()
        }
        super.init()
    }

    func requestAuthorization() {
        state = .requestingAuth
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.onAuthorization?(status)
                self?.state = (status == .authorized) ? .ready : .idle
            }
        }
    }

    func startRecording(category: AVAudioSession.Category = .record, mode: AVAudioSession.Mode = .measurement) {
        guard state == .ready || state == .idle else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            onError?(NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"]))
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(category, mode: mode, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onError?(error)
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }
        request.shouldReportPartialResults = true
        if #available(iOS 17, *) { request.addsPunctuation = true }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onError?(error)
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self?.onFinalResult?(text)
                    self?.stopRecording()
                } else {
                    self?.onPartialResult?(text)
                }
            }
            if let error = error {
                self?.onError?(error)
                self?.stopRecording()
            }
        }

        state = .recognizing
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {}
        state = .ready
    }
}
