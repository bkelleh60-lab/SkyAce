import Foundation
import AVFoundation
import SpriteKit

/// Plays background music (AVAudioPlayer) and short SFX (SKAction).
/// Respects user toggles stored in ProgressManager.
///
/// Three independent AVAudioPlayer slots:
///   - `musicPlayer`  — looping background track (menu / gameplay / Free Flight).
///   - `enginePlayer` — looping plane engine ambience that runs alongside the
///     music track during flight (SKY-75). Held in a dedicated slot because
///     `playMusic` is single-instance — loading the engine loop through it
///     would silence the level music.
///   - `loopingSfxPlayer` — looping SFX layer (e.g. timer warning) so a
///     repeating cue can be started and stopped on demand without colliding
///     with the engine loop or music.
final class AudioManager {

    static let shared = AudioManager()

    private var musicPlayer: AVAudioPlayer?
    private var currentTrack: String?

    private var enginePlayer: AVAudioPlayer?
    private var currentEngineLoop: String?

    private var loopingSfxPlayer: AVAudioPlayer?
    private var currentLoopingSfx: String?

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
            if !newValue {
                stopMusic()
                stopEngineLoop()
                stopLoopingSFX()
            }
        }
    }

    var sfxEnabled: Bool {
        get { ProgressManager.shared.sfxEnabled }
        set {
            ProgressManager.shared.sfxEnabled = newValue
            if !newValue { stopLoopingSFX() }
        }
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

    // MARK: - Engine loop (SKY-75)

    /// Default engine-loop volume. Sits ~40% below the music default (0.6) so
    /// the engine ambience reads as background texture, not a competing layer.
    static let engineLoopDefaultVolume: Float = 0.35

    /// Starts a looping engine track in the engine slot. Coexists with the
    /// active music track. Reuses the existing player if the same loop is
    /// already running so a scene transition into the same plane doesn't
    /// restart the cycle audibly.
    func playEngineLoop(_ fileName: String, fileExtension: String = "caf", volume: Float = engineLoopDefaultVolume) {
        // Engine ambience tracks the music toggle — same "background sound"
        // class as the music itself, and a player who muted music would
        // expect the plane to fall silent too.
        guard musicEnabled else { return }
        let key = "\(fileName).\(fileExtension)"
        if currentEngineLoop == key, enginePlayer?.isPlaying == true { return }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()
            player.play()
            enginePlayer = player
            currentEngineLoop = key
        } catch {
            // Engine asset missing — gameplay continues without the ambience layer.
        }
    }

    func stopEngineLoop() {
        enginePlayer?.stop()
        enginePlayer = nil
        currentEngineLoop = nil
    }

    func fadeOutEngineLoop(duration: TimeInterval = 0.4) {
        guard let player = enginePlayer else { return }
        let start = player.volume
        let steps = 20
        let interval = duration / Double(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
                guard let self = self, let player = self.enginePlayer else { return }
                player.volume = start * Float(1 - Double(i) / Double(steps))
                if i == steps { self.stopEngineLoop() }
            }
        }
    }

    // MARK: - Looping SFX (SKY-75)

    /// Starts a looping SFX cue in its own slot, alongside music + engine. Used
    /// for cues that need to repeat while a state holds (e.g. timer warning).
    /// No-op if the same loop is already playing.
    func playLoopingSFX(_ fileName: String, fileExtension: String = "caf", volume: Float = 0.7) {
        guard sfxEnabled else { return }
        let key = "\(fileName).\(fileExtension)"
        if currentLoopingSfx == key, loopingSfxPlayer?.isPlaying == true { return }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()
            player.play()
            loopingSfxPlayer = player
            currentLoopingSfx = key
        } catch {
            // Audio file may be a placeholder during development.
        }
    }

    func stopLoopingSFX() {
        loopingSfxPlayer?.stop()
        loopingSfxPlayer = nil
        currentLoopingSfx = nil
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

    // SKY-75 additions. CAF instead of WAV — the assets ship as CAF for
    // lowest-latency playback and best loop performance on iOS.
    static let timerWarning      = "sfx_timer_warning"
    static let landingTouchdown  = "sfx_landing_touchdown"
    static let landingSuccess    = "sfx_landing_success"
    static let landingRough      = "sfx_landing_rough"
    static let landingCrash      = "sfx_landing_crash"
}

enum SkyMusic {
    static let menu             = "menu_music"
    static let gameplay         = "gameplay_music"
    static let freeFlightCity   = "freeflight_city_music"
    static let freeFlightMntn   = "freeflight_mountain_music"

    // SKY-75 — Landing Practice mode (SKY-83) ships its own music track.
    static let landingPractice  = "music_landing_practice"
}

/// SKY-75 engine ambience. One loop per plane; file naming matches
/// `PlaneCatalog` ID strings so the active loop can be derived from
/// `ProgressManager.shared.selectedPlaneID` without a separate map.
enum SkyEngineLoop {
    /// Prefix shared by every engine asset filename.
    static let filenamePrefix = "engine_loop_"

    /// Filename (without extension) of the engine loop for a given plane ID.
    /// Direct concatenation — `AudioManager.playEngineLoop` resolves the
    /// resource via `Bundle.main.url(forResource:withExtension:)` with no
    /// string transformation.
    static func filename(forPlaneID planeID: String) -> String {
        return filenamePrefix + planeID
    }
}
