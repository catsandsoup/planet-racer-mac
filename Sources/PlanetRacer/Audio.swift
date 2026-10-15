import AVFoundation
import PlanetRacerCore

/// Sounds from assets/sounds, driven the way the original's sfxEngine / playLoop / speelSimpelSFX did.
final class Audio {
    private var data: [String: Data] = [:]
    private var oneShots: [AVAudioPlayer] = []
    private var music: AVAudioPlayer?
    private var musicName = ""
    private var engineStart: AVAudioPlayer?
    private var engineLoop: AVAudioPlayer?
    private var burner: AVAudioPlayer?
    private var engineStep = 0      // 0 off, 1 start sample, 2 looping
    private var musicVolume: Float = 0.8, effectsVolume: Float = 0.8, musicFade: Float = 1
    private var paused = false

    init(root: URL) {
        let dir = root.appendingPathComponent("assets/sounds")
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            data[url.deletingPathExtension().lastPathComponent] = try? Data(contentsOf: url)
        }
    }

    private func player(_ name: String, loop: Bool = false) -> AVAudioPlayer? {
        guard let d = data[name], let p = try? AVAudioPlayer(data: d) else { return nil }
        p.numberOfLoops = loop ? -1 : 0
        p.prepareToPlay()
        return p
    }

    func setVolumes(music m: Int, effects e: Int) {
        musicVolume = Float(m) / 10
        effectsVolume = Float(e) / 10
        music?.volume = musicVolume * musicFade
        engineLoop?.volume = effectsVolume * 0.8
        burner?.volume = effectsVolume * 0.3
    }

    func playMusic(_ name: String) {
        guard name != musicName else { return }
        stopMusic()
        musicName = name
        musicFade = 1
        music = player(name, loop: true)
        music?.volume = musicVolume
        music?.play()
    }

    func stopMusic() {
        music?.stop()
        music = nil
        musicName = ""
    }

    func play(_ name: String, volume: Float = 1) {
        oneShots.removeAll { !$0.isPlaying }
        guard let p = player(name) else { return }
        p.volume = volume * effectsVolume
        p.play()
        oneShots.append(p)
    }

    func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        for pl in [music, engineStart, engineLoop, burner] + oneShots.map(Optional.some) {
            guard let pl else { continue }
            if p { pl.pause() } else if pl.currentTime > 0 || pl === music { pl.play() }
        }
    }

    func stopRaceLoops() {
        engineStart?.stop(); engineLoop?.stop(); burner?.stop()
        engineStart = nil; engineLoop = nil; burner = nil
        engineStep = 0
    }

    /// Per frame during a race: play queued race sounds and keep the engine/afterburner loops in step.
    func update(game: OpaquePointer, frame f: PRFrame) {
        var id: Int32 = 0
        var vol: Float = 0
        while pr_race_poll_sfx(game, &id, &vol) {
            switch Int(id) {
            case Int(PR_SFX_START): play("startrace")
            case Int(PR_SFX_HIT_GROUND): play("hitground", volume: vol)
            case Int(PR_SFX_HIT_ROOF): play("hitroof", volume: vol)
            case Int(PR_SFX_CRASH): play("crash"); play("crash_KO")
            case Int(PR_SFX_FINISH): play("finish"); play("finish2")
            case Int(PR_SFX_LOSE): play("lose"); play("finish2")
            case Int(PR_SFX_AMBIENT): play("random\(Int.random(in: 1...3))", volume: vol)
            default: break
            }
        }
        musicFade = Float(f.musicFade)
        music?.volume = musicVolume * musicFade

        let n = max(1, min(3, Int(f.engineSound)))
        if f.engineOn {
            if engineStep == 0 {
                engineStep = 1
                engineStart = player("engine_start\(n)")
                engineStart?.volume = effectsVolume * 0.8
                engineStart?.play()
            } else if engineStep == 1, engineStart?.isPlaying != true {
                engineStep = 2
                engineLoop = player("engine\(n)", loop: true)
                engineLoop?.volume = effectsVolume * 0.8
                engineLoop?.play()
                stopMusic() // the original stops the race music once the engine loop takes over
            }
        } else if engineStep != 0 {
            engineStart?.stop(); engineLoop?.stop()
            engineStart = nil; engineLoop = nil
            engineStep = 0
            play("engine_fade\(n)", volume: 0.8)
        }

        if f.boosting, burner == nil {
            burner = player("afterburner", loop: true)
            burner?.volume = effectsVolume * 0.3
            burner?.play()
        } else if !f.boosting, burner != nil {
            burner?.stop()
            burner = nil
        }
    }
}
