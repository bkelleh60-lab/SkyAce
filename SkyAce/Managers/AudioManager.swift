import Foundation
import AVFoundation
import SpriteKit

/// Plays background music (AVAudioPlayer) and short SFX (SKAction).
/// Respects user toggles stored in ProgressManager.
final class AudioManager {

    static let shared = AudioManager()

    private var musicPlayer: AVAudioPlayer?
    private var currentTrack: String?

    private init() {
        configureSession()
    }

    // MARK: - Session

    private func configureSession() {
        do {
            // .ambient — music mixes with other audio, respects silent switch.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Silent failure — audio is non-critical to gameplay.
        }
    }

    // MARK: - Toggles

    var musicEnabled: Bool {
        get { ProgressManager.shared.musicEnabled }
        set {
            ProgressManager.shared.musicEnabled = newValue
            if !newValue { stopMusic() }
        }
    }

    var sfxEnabled: Bool {
        get { ProgressManager.shared.sfxEnabled }
        set { ProgressManager.shared.sfxEnabled = newValue }
    }

    // MARK: - Music

    /// Starts a looping track. No-op if the same track is already playing.
    func playMusic(_ fileName: String, fileExtension: String = "wav", volume: Float = 0.6) {
        guard musicEnabled else { return }
        let trackKey = "\(fileName).\(fileExtension)"
        if currentTrack == trackKey, musicPlayer?.isPlaying == true { return }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()
            player.play()
            musicPlayer = player
            currentTrack = trackKey
        } catch {
            // Audio file may be a placeholder during development.
        }
    }

    func stopMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        currentTrack = nil
    }

    func fadeOutMusic(duration: TimeInterval = 0.4) {
        guard let player = musicPlayer else { return }
        let start = player.volume
        let steps = 20
        let interval = duration / Double(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
                guard let self = self, let player = self.musicPlayer else { return }
                player.volume = start * Float(1 - Double(i) / Double(steps))
                if i == steps { self.stopMusic() }
            }
        }
    }

    // MARK: - SFX — returns an SKAction so scenes can run it on any node

    /// Build an SKAction that plays a short sound. Returns a no-op if SFX is
    /// disabled so callers don't need to branch.
    func sfxAction(_ fileName: String, fileExtension: String = "wav") -> SKAction {
        guard sfxEnabled else { return SKAction.wait(forDuration: 0) }
        // SKAction.playSoundFileNamed takes a "file.ext" string.
        return SKAction.playSoundFileNamed("\(fileName).\(fileExtension)", waitForCompletion: false)
    }

    /// Convenience for scenes that want fire-and-forget playback on a given node.
    func playSFX(_ fileName: String, fileExtension: String = "wav", on node: SKNode) {
        guard sfxEnabled else { return }
        node.run(sfxAction(fileName, fileExtension: fileExtension))
    }
}

// Standard SFX filenames — kept as constants so scenes don't have to remember strings.
enum SkySFX {
    static let coinCollect = "coin_collect"
    static let ringPass    = "ring_pass"
    static let hit         = "hit"
    static let fail        = "fail"
    static let win         = "win"
    static let uiTap       = "ui_tap"
}

enum SkyMusic {
    static let menu             = "menu_music"
    static let gameplay         = "gameplay_music"
    static let freeFlightCity   = "freeflight_city_music"
    static let freeFlightMntn   = "freeflight_mountain_music"
}
