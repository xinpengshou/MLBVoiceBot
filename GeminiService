import Foundation
import AVFoundation

class GeminiService: NSObject, ObservableObject {
    private let baseURL = "http://localhost:8000/gemini"
    private var audioPlayer: AVAudioPlayer?
    
    @Published var isPlaying: Bool = false
    @Published var shouldResetBaseball: Bool = false
    
    func sendTextToGemini(_ text: String) async throws -> (String, Data?) {
        shouldResetBaseball = false
        let body = ["text": text]
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GeminiResponseWithAudio.self, from: data)
        
        return (response.response, response.audio.flatMap { Data(base64Encoded: $0) })
    }
    
    func playAudio(_ audioData: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            shouldResetBaseball = false
        } catch {
            print("Error playing audio: \(error)")
        }
    }
    
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        shouldResetBaseball = true
    }
}

extension GeminiService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        isPlaying = false
        shouldResetBaseball = true
    }
}

struct GeminiResponseWithAudio: Codable {
    let response: String
    let audio: String?
} 
