import AVFoundation
import Foundation

@MainActor
final class AudioPlayer {
    static let shared = AudioPlayer()

    /// Retained so playback isn't cut off when the local scope exits.
    private var player: AVAudioPlayer?

    func play(_ sound: CelebrationSound) {
        guard let url = Bundle.module.url(forResource: sound.fileName, withExtension: "mp3") else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            // A missing/corrupt clip shouldn't crash the app; just stay silent.
        }
    }

    func preview(_ sound: CelebrationSound) {
        play(sound)
    }
}
