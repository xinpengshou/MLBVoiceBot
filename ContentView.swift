import SwiftUI
import AVFoundation
import Speech

class SpeechRecognitionManager: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var currentText = ""
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5
    
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    @Published var shouldSendToGemini = false
    
    private func resetAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error resetting audio session: \(error)")
        }
    }
    
    func startRecording() {
        guard !isRecording,
              let recognizer = speechRecognizer,
              recognizer.isAvailable else { return }
        
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.inputFormat(forBus: 0)
            
            // Setup recognition task
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Recognition error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.resetAndRestartRecording()
                    }
                    return
                }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        if text != self.currentText {
                            print("Detected: \(text)")
                            self.currentText = text
                            
                            self.silenceTimer?.invalidate()
                            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.silenceThreshold, repeats: false) { [weak self] _ in
                                self?.shouldSendToGemini = true
                            }
                        }
                    }
                }
            }
            
            // Setup audio tap
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                
                let channelData = buffer.floatChannelData?[0]
                if let data = channelData {
                    let frames = Float(buffer.frameLength)
                    var sum: Float = 0
                    for frame in 0..<Int(frames) {
                        sum += abs(data[frame])
                    }
                    DispatchQueue.main.async {
                        self?.audioLevel = sum / frames * 5
                    }
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            print("Started recording...")
            
        } catch {
            print("Recording failed to start: \(error)")
            stopRecording()
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        audioLevel = 0.0
        currentText = ""
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error stopping audio session: \(error)")
        }
    }
    
    private func resetAndRestartRecording() {
        stopRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startRecording()
        }
    }
}

struct ContentView: View {
    @StateObject private var speechManager = SpeechRecognitionManager()
    @StateObject private var geminiService = GeminiService()
    @State private var isEnlarged = false
    @State private var rotation: Double = 0
    @State private var geminiResponse = ""
    
    var baseSize: CGFloat {
        isEnlarged ? 400 : 350
    }
    
    var imageSize: CGFloat {
        if speechManager.isRecording {
            return baseSize + (CGFloat(speechManager.audioLevel) * 30)
        } else {
            return baseSize
        }
    }
    
    var body: some View {
        ZStack {
            Color(red: 255/255, green: 236/255, blue: 66/255)
                .ignoresSafeArea()
            
            Image("baseball")
                .resizable()
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)
                .rotationEffect(.degrees(rotation))
                .animation(
                    .spring(
                        response: 0.5,
                        dampingFraction: 0.6,
                        blendDuration: 0
                    ),
                    value: isEnlarged
                )
                .animation(
                    .spring(
                        response: 0.5,
                        dampingFraction: 0.6
                    ),
                    value: rotation
                )
                .animation(
                    .spring(
                        response: 0.1,
                        dampingFraction: 0.5
                    ),
                    value: speechManager.audioLevel
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        isEnlarged.toggle()
                        rotation = rotation == 0 ? 15 : 0
                        
                        if speechManager.isRecording {
                            speechManager.stopRecording()
                            geminiService.stopAudio()
                        } else {
                            // Clean up before starting
                            geminiService.stopAudio()
                            geminiService.shouldResetBaseball = false
                            // Add a small delay before starting recording
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                speechManager.startRecording()
                            }
                        }
                    }
                }
        }
        .onAppear {
            SFSpeechRecognizer.requestAuthorization { _ in }
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
        .onChange(of: geminiService.shouldResetBaseball) { shouldReset in
            if shouldReset {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    isEnlarged = false
                    rotation = 0
                    // Stop recording when Gemini finishes talking
                    if speechManager.isRecording {
                        speechManager.stopRecording()
                    }
                }
            }
        }
        .onChange(of: speechManager.shouldSendToGemini) { newValue in
            if newValue {
                Task {
                    do {
                        let (response, audioData) = try await geminiService.sendTextToGemini(speechManager.currentText)
                        
                        await MainActor.run {
                            geminiResponse = response
                            print("\nUser: \(speechManager.currentText)")
                            print("Gemini: \(response)\n")
                            
                            if let audioData = audioData {
                                geminiService.playAudio(audioData)
                            }
                        }
                    } catch {
                        print("Error: \(error.localizedDescription)")
                    }
                    speechManager.shouldSendToGemini = false
                }
            }
        }
    }
}

// Helper extension to clamp values
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview {
    ContentView()
}

